#!/bin/sh
set -e
python manage.py makemigrations api --noinput >/dev/null
python manage.py migrate --noinput
python manage.py collectstatic --noinput >/dev/null
python manage.py seed
exec python manage.py runserver 0.0.0.0:8000 --noreload
