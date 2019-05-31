FROM ubuntu:18.10 AS build

ENV DEBIAN_FRONTEND noninteractive
ENV PYTHONUNBUFFERED 1

# Install runtime packages
RUN apt-get -yqq update && \
    apt-get -yqq install --no-install-recommends \
        curl \
        git \
        gcc \
        python-pip \
        python-dev \
        python-setuptools \
        libldap2-dev \
        libsasl2-dev \
        libmagic-dev \
        libmagickwand-dev \
        libglu1-mesa-dev \
        libxi6 \
        mc \
        ncdu && \
    pip install --no-cache-dir --upgrade pip

# Install NodeJS
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash - && \
    apt-get -yqq update && \
    apt-get -yqq install --no-install-recommends nodejs

# Create runtime user
RUN mkdir -p /app && \
    groupadd -r -g 1001 mytardis && \
    useradd -r -u 1001 -g 1001 mytardis && \
    chown mytardis:mytardis -R /app

WORKDIR /app

# Clone MyTardis and MyData repos
RUN git clone --depth 1 --branch develop \
    https://github.com/mytardis/mytardis.git ./ && \
    git clone --depth 1 --branch master \
    https://github.com/mytardis/mytardis-app-mydata.git ./tardis/apps/mydata/ && \
    # Cleanup
    rm -rf /app/.git* && \
    rm -rf /app/tardis/apps/mydata/.git*

# Copy k8s-related requirements
COPY requirements.txt ./

# Install Python packages
RUN cat requirements.txt \
    requirements-base.txt \
    requirements-postgres.txt \
    requirements-ldap.txt \
    tardis/apps/social_auth/requirements.txt \
    tardis/apps/mydata/requirements.txt \
    > /tmp/requirements.txt && \
    # Display packages
    sort /tmp/requirements.txt && \
    # Don't install repos in edit mode
    sed -i 's/-e git+/git+/g' /tmp/requirements.txt && \
    pip install --no-cache-dir -q -r /tmp/requirements.txt

# Install NodeJS packages
RUN npm install --production --no-cache --quiet --depth 0 && \
    npm run-script build --no-cache --quiet

FROM build AS production

# Cleanup
RUN rm -rf /app/node_modules && \
    rm -rf /app/false && \
    apt-get -y remove --purge \
        gcc \
        git

# Copy k8s-related code
COPY settings.py ./tardis/
COPY beat.py ./
COPY entrypoint.sh ./

USER mytardis
EXPOSE 8000

CMD ["sh", "entrypoint.sh"]

FROM build AS test

# Add Chrome repo
RUN curl -sS -o - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list

# Install utilities
RUN apt-get -yqq update && \
    apt-get -yqq install --no-install-recommends \
        unzip \
        libmysqlclient-dev \
        google-chrome-stable

# Install Chrome WebDriver
RUN CHROMEDRIVER_VERSION=`curl -sS https://chromedriver.storage.googleapis.com/LATEST_RELEASE` && \
    mkdir -p /opt/chromedriver-$CHROMEDRIVER_VERSION && \
    curl -sS -o /tmp/chromedriver_linux64.zip https://chromedriver.storage.googleapis.com/$CHROMEDRIVER_VERSION/chromedriver_linux64.zip && \
    unzip -qq /tmp/chromedriver_linux64.zip -d /opt/chromedriver-$CHROMEDRIVER_VERSION && \
    rm /tmp/chromedriver_linux64.zip && \
    chmod +x /opt/chromedriver-$CHROMEDRIVER_VERSION/chromedriver && \
    ln -fs /opt/chromedriver-$CHROMEDRIVER_VERSION/chromedriver /usr/local/bin/chromedriver

# Install Python packages
RUN cat requirements-mysql.txt \
    requirements-test.txt \
    > /tmp/requirements.txt && \
    pip install --no-cache-dir -q -r /tmp/requirements.txt

# Install NodeJS packages
RUN npm install --no-cache --quiet --depth 0

# Create default storage
RUN mkdir -p var/store

# This will keep container running...
CMD ["tail", "-f", "/dev/null"]
