import os
import urllib
import yaml
from .default_settings import *

settings_filename = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                                 'settings.yaml')
if os.path.isfile(settings_filename):
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
        'NAME': data['postgres']['name']
    }

    CELERY_RESULT_BACKEND = 'amqp'
    BROKER_URL = 'amqp://%(user)s:%(password)s@%(host)s:%(port)s/%(vhost)s' % {
        'host': data['rabbitmq']['host'],
        'port': data['rabbitmq']['port'],
        'user': data['rabbitmq']['user'],
        'password': urllib.quote_plus(data['rabbitmq']['password'],),
        'vhost': data['rabbitmq']['vhost']
    }

    STATIC_ROOT = data['static_files_path']
    DEFAULT_STORAGE_BASE_DIR = data['default_store_path']
    METADATA_STORE_PATH = data['metadata_store_path']

    EMAIL_HOST = data['email']['host']
    EMAIL_PORT = data['email']['port']
    DEFAULT_FROM_EMAIL = data['email']['from']

    ADMINS = []
    for user in data['admins']:
        ADMINS.append((user['name'], user['email']))
    MANAGERS = ADMINS


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
    }
}

SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTOCOL', 'https')
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
DEFAULT_ARCHIVE_FORMATS = ['tar']
REDIS_VERIFY_MANAGER = False
