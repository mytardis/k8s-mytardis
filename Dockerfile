FROM ubuntu:18.04 AS base

# Upgrade OS and install packages
RUN apt-get update -yqq && \
    apt-get install -yqq --no-install-recommends \
        build-essential \
        curl \
        git \
        gnupg \
        libfreetype6-dev \
        libjpeg-dev \
        libldap2-dev \
        libmagic-dev \
        libmagickwand-dev \
        libmysqlclient-dev \
        libmysqlclient20 \
        libsasl2-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        python-dev \
        python-pip \
        python-setuptools \
        zlib1g-dev \
        unzip \
        mc \
        ncdu && \
	rm -rf /var/lib/apt/lists/*

# Install NodeJS
RUN curl -sL https://deb.nodesource.com/setup_10.x | bash - && \
    apt-get update -yqq && \
    apt-get install -yqq --no-install-recommends \
        nodejs && \
	rm -rf /var/lib/apt/lists/*

# Upgrade PIP
RUN pip install --upgrade --no-cache-dir pip

FROM base AS builder

ENV PYTHONUNBUFFERED 1
ENV PYTHONDONTWRITEBYTECODE 1

WORKDIR /app

COPY mytardis/requirements-base.txt ./
# don't install Git repos in 'edit' mode
RUN sed -i 's/-e git+/git+/g' requirements-base.txt
RUN pip install -q -r requirements-base.txt

COPY mytardis/requirements-postgres.txt ./
RUN pip install -q -r requirements-postgres.txt

COPY mytardis/tardis/apps/social_auth/requirements*.txt ./requirements-auth.txt
RUN pip install -q -r requirements-auth.txt

#RUN git clone https://github.com/wettenhj/mytardis-app-mydata.git ./tardis/apps/mydata/
#RUN pip install -r tardis/apps/mydata/requirements.txt

COPY mytardis/package.json .

RUN npm set progress=false && \
    npm config set depth 0 && \
    npm install --production

FROM builder AS production

COPY mytardis/ .

COPY settings.py ./tardis/
COPY beat.py ./tardis/

EXPOSE 8000

CMD ["gunicorn", "--bind", ":8000", "--config", "gunicorn_settings.py", "wsgi:application"]

FROM builder AS test

# Install Chrome WebDriver
RUN CHROMEDRIVER_VERSION=`curl -sS https://chromedriver.storage.googleapis.com/LATEST_RELEASE` && \
    mkdir -p /opt/chromedriver-$CHROMEDRIVER_VERSION && \
    curl -sS -o /tmp/chromedriver_linux64.zip https://chromedriver.storage.googleapis.com/$CHROMEDRIVER_VERSION/chromedriver_linux64.zip && \
    unzip -qq /tmp/chromedriver_linux64.zip -d /opt/chromedriver-$CHROMEDRIVER_VERSION && \
    rm /tmp/chromedriver_linux64.zip && \
    chmod +x /opt/chromedriver-$CHROMEDRIVER_VERSION/chromedriver && \
    ln -fs /opt/chromedriver-$CHROMEDRIVER_VERSION/chromedriver /usr/local/bin/chromedriver

# Setup Google Chrome repo
RUN curl -sS -o - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list

# Install Google Chrome
RUN apt-get -yqq update && \
    apt-get -yqq install google-chrome-stable && \
    apt-get clean

# Install PhantomJS
RUN PHANTOMJS_CDNURL=https://npm.taobao.org/mirrors/phantomjs/ npm install phantomjs-prebuilt

# Install MySQL packages
COPY mytardis/requirements-mysql.txt ./
RUN pip install -q -r requirements-mysql.txt

# Install test packages
COPY mytardis/requirements-test.txt ./
RUN pip install -q -r requirements-test.txt

# Install NodeJS packages
RUN npm install

# Create default storage
RUN mkdir -p var/store

COPY . .

# Remove production settings
# RUN rm -f ./tardis/settings.py

# This will keep container running...
CMD ["tail", "-f", "/dev/null"]
