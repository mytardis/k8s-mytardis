import os
import urllib
import yaml
import json
from datetime import timedelta

import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

from .default_settings import *

settings_filename = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                                 'settings.yaml')
assert os.path.isfile(settings_filename)
with open(settings_filename) as settings_file:
    data = yaml.load(settings_file, Loader=yaml.FullLoader)

DEBUG = data['debug']
SECRET_KEY = data['secret_key']

DATABASES['default'] = {
    'ENGINE': 'django.db.backends.postgresql_psycopg2',
    'HOST': data['postgres']['host'],
    'PORT': data['postgres']['port'],
    'USER': data['postgres']['user'],
    'PASSWORD': data['postgres']['password'],
    'NAME': data['postgres']['name'],
    'CONN_MAX_AGE': data['postgres'].get('conn_max_age')  # None means re-use connections
}

CELERY_RESULT_BACKEND = 'amqp'
BROKER_URL = 'amqp://%(user)s:%(password)s@%(host)s:%(port)s/%(vhost)s' % {
    'host': data['rabbitmq']['host'],
    'port': data['rabbitmq']['port'],
    'user': data['rabbitmq']['user'],
    'password': urllib.quote_plus(data['rabbitmq']['password'],),
    'vhost': data['rabbitmq']['vhost']
}

DEFAULT_STORAGE_BASE_DIR = data['default_store_path']
METADATA_STORE_PATH = data['metadata_store_path']

EMAIL_HOST = data['email']['host']
EMAIL_PORT = data['email']['port']
DEFAULT_FROM_EMAIL = data['email']['from']
SERVER_EMAIL = data['email']['server']

ADMINS = []
for user in data['admins']:
    ADMINS.append((user['name'], user['email']))
MANAGERS = ADMINS

INSTALLED_APPS += tuple(data['installed_apps'])


CELERY_QUEUES += (
    Queue('filters', Exchange('filters'),
          routing_key='filters',
          queue_arguments={'x-max-priority': MAX_TASK_PRIORITY}),
)

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'console': {
            'format': '%(asctime)s %(name)-12s %(levelname)-8s %(message)s',
        },
        'django': {
            'format': 'django: %(message)s',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'console',
        },
        'syslog': {
            'class': 'logging.handlers.SysLogHandler',
            'level': 'ERROR',
            'facility': 'user',
            'formatter': 'django'
        },
    },
    'loggers': {
        '': {
            'handlers': ['console', 'syslog'],
            'level': 'ERROR'
        },
        # Redefining the logger for the `django` module
        # prevents invoking the `AdminEmailHandler`
        'django': {
            'handlers': ['console'],
            'level': 'INFO'
        }
    }
}

SECURE_PROXY_SSL_HEADER = ('HTTP_X_ORIGINAL_PROTO', 'https')
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
DEFAULT_ARCHIVE_FORMATS = ['tar']
REDIS_VERIFY_MANAGER = False

# SFTP settings
if 'sftp' in data:
    SFTP_GEVENT = data['sftp']['gevent']
    SFTP_HOST_KEY = data['sftp']['host_key']
    SFTP_PORT = data['sftp']['port']
    SFTP_USERNAME_ATTRIBUTE = data['sftp']['username_attribute']

# Set auth and group providers if specified in yaml data:
if 'auth_providers' in data:
    AUTH_PROVIDERS = tuple(data.get('auth_providers'))
if 'group_providers' in data:
    GROUP_PROVIDERS = tuple(data.get('group_providers'))

# Set authentication backends if specified in yaml data:
if 'authentication_backends' in data:
    AUTHENTICATION_BACKENDS = tuple(data.get('authentication_backends'))

# Context processors
TEMPLATES[0]['OPTIONS']['context_processors'].extend(
    data.get('context_processors', []))

# Override default middleware if specified in yaml data:
if 'middleware' in data:
    MIDDLEWARE = data.get('middleware')

# LDAP configuration
LDAP_USE_TLS = data.get('ldap_use_tls', False)
LDAP_URL = data.get('ldap_url', '')
LDAP_USER_LOGIN_ATTR = data.get('ldap_user_login_attr', '')
LDAP_USER_ATTR_MAP = {key: value for key, value in
                      data.get('ldap_user_attr_map', {}).items()}
LDAP_GROUP_ID_ATTR = data.get('ldap_group_id_attr', '')
LDAP_GROUP_ATTR_MAP = {key: value for key, value in
                       data.get('ldap_group_attr_map', {}).items()}
LDAP_ADMIN_USER = data.get('ldap_admin_user', '')
LDAP_ADMIN_PASSWORD = data.get('ldap_admin_password', '')
LDAP_BASE = data.get('ldap_base', '')
LDAP_USER_BASE = data.get('ldap_user_base', '')
LDAP_GROUP_BASE = data.get('ldap_group_base', '')

# Overridable login views
if 'login_views' in data:
    LOGIN_VIEWS_FROM_YAML = data.get('login_views')
    LOGIN_VIEWS = { int(key): LOGIN_VIEWS_FROM_YAML[key] for key in LOGIN_VIEWS_FROM_YAML.keys() }

# Add arbitrary string attributes as defined in settings.yaml:
for name, value in data.get('other_settings', {}).items():
    globals()[name] = value

# Git version info (passed via env variable in JSON format)
ver = os.environ.get('MYTARDIS_VERSION', '')
if len(ver):
    MYTARDIS_VERSION = json.loads(ver)

if 'sentry_dsn' in data:
    sentry_sdk.init(
        dsn=data.get('sentry_dsn'),
        integrations=[DjangoIntegration()]
    )

CELERYBEAT_SCHEDULE = {}
for name, params in data.get('celerybeat_schedule', {}).items():
    CELERYBEAT_SCHEDULE[name] = {
        'task': params['task'],
        'schedule': timedelta(
            days=params['schedule'].get('days', 0),
            seconds=params['schedule'].get('seconds', 0),
            microseconds=params['schedule'].get('microseconds', 0),
            milliseconds=params['schedule'].get('milliseconds', 0),
            minutes=params['schedule'].get('minutes', 0),
            hours=params['schedule'].get('hours', 0),
            weeks=params['schedule'].get('weeks', 0)
        ),
        'kwargs': params.get('kwargs', {'priority': DEFAULT_TASK_PRIORITY})
    }
