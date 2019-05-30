#!/bin/sh

gunicorn --bind :8000 --config gunicorn_settings.py wsgi:application
