FROM ubuntu:18.10 AS build

ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE DontWarn
ENV DEBIAN_FRONTEND noninteractive
ENV PYTHONUNBUFFERED 1

# Create runtime user
RUN mkdir -p /app && \
    groupadd -r -g 1001 mytardis && \
    useradd -r -m -u 1001 -g 1001 mytardis

WORKDIR /app

# Copy Python requirements
COPY requirements.txt \
     submodules/mytardis/requirements-base.txt \
     submodules/mytardis/requirements-postgres.txt \
     submodules/mytardis/requirements-ldap.txt \
     ./
COPY submodules/mytardis/tardis/apps/social_auth/requirements.txt ./requirements-auth.txt
COPY submodules/mytardis-app-mydata/requirements.txt ./requirements-mydata.txt

# Install Python packages
RUN apt-get -yqq update && \
    apt-get -yqq install --no-install-recommends -o=Dpkg::Use-Pty=0 \
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
        ncdu \
        vim-tiny \
    > /dev/null 2>&1 && \
    cat requirements.txt \
        requirements-base.txt \
        requirements-postgres.txt \
        requirements-ldap.txt \
        requirements-auth.txt \
        requirements-mydata.txt \
        > /tmp/requirements.txt && \
    cat /tmp/requirements.txt | egrep -v '^\s*(#|$)' | sort && \
    pip install --no-cache-dir -q -r /tmp/requirements.txt && \
    apt-get -y remove --purge \
        gcc \
        git && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy NodeJS requirements
COPY submodules/mytardis/package.json ./
COPY submodules/mytardis/webpack.config.js ./
COPY submodules/mytardis/assets/ assets/
COPY submodules/mytardis/.babelrc ./

# Install NodeJS packages
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash - && \
    apt-get -yqq update && \
    apt-get -yqq install --no-install-recommends -o=Dpkg::Use-Pty=0 \
        nodejs \
    > /dev/null 2>&1 && \
    npm install --production --no-cache --quiet --depth 0 && \
    npm run-script build --no-cache --quiet && \
    rm -rf /app/node_modules && \
    rm -rf /app/false && \
    apt-get -y remove --purge \
        nodejs && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

FROM build AS production

# Copy app code
COPY submodules/mytardis/ ./
COPY submodules/mytardis-app-mydata/ tardis/apps/mydata/

# Copy k8s-related code
COPY settings.py ./tardis/
COPY beat.py ./
COPY entrypoint.sh ./

RUN chown -R mytardis:mytardis /app
USER mytardis
EXPOSE 8000

CMD ["sh", "entrypoint.sh"]

FROM build AS test

USER root

# Add Chrome repo
RUN curl -sS -o - https://dl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list

# Copy Python packages
COPY submodules/mytardis/requirements-mysql.txt \
     submodules/mytardis/requirements-test.txt \
     ./

# Install Python packages and utilities
RUN apt-get -yqq update && \
    apt-get -yqq install --no-install-recommends -o=Dpkg::Use-Pty=0 \
        google-chrome-stable \
        gcc \
        unzip \
        libmysqlclient-dev \
    > /dev/null 2>&1 && \
    cat requirements-mysql.txt \
        requirements-test.txt \
        > /tmp/requirements.txt && \
    pip install --no-cache-dir -q -r /tmp/requirements.txt && \
    apt-get -y remove --purge \
        gcc && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Chrome WebDriver
RUN CHROMEDRIVER_VERSION=`curl -sS https://chromedriver.storage.googleapis.com/LATEST_RELEASE` && \
    mkdir -p /opt/chromedriver-$CHROMEDRIVER_VERSION && \
    curl -sS -o /tmp/chromedriver_linux64.zip https://chromedriver.storage.googleapis.com/$CHROMEDRIVER_VERSION/chromedriver_linux64.zip && \
    unzip -qq /tmp/chromedriver_linux64.zip -d /opt/chromedriver-$CHROMEDRIVER_VERSION && \
    rm /tmp/chromedriver_linux64.zip && \
    chmod +x /opt/chromedriver-$CHROMEDRIVER_VERSION/chromedriver && \
    ln -fs /opt/chromedriver-$CHROMEDRIVER_VERSION/chromedriver /usr/local/bin/chromedriver

# Install NodeJS packages
RUN apt-get -yqq update && \
    apt-get -yqq install --no-install-recommends -o=Dpkg::Use-Pty=0 \
        nodejs \
    > /dev/null 2>&1 && \
    npm install --no-cache --quiet --depth 0 && \
    apt-get -y remove --purge \
        gcc && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create default storage
RUN mkdir -p var/store

# Copy app code
COPY submodules/mytardis/ \
     submodules/mytardis/.pylintrc \
     submodules/mytardis/.eslintrc \
     ./
COPY submodules/mytardis-app-mydata/ tardis/apps/mydata/

# This will keep container running...
CMD ["tail", "-f", "/dev/null"]
