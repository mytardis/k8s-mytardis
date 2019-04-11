from datetime import datetime, timedelta
from celery.beat import Service
from tardis.celery import tardis_app


schedule = Service(tardis_app).get_scheduler().get_schedule()
now = datetime.utcnow()

for task_name, task in schedule.items():
    next_run = task.last_run_at.replace(tzinfo=None) + task.schedule.run_every
    print("{}: check if {} is less than {}".format(task_name, now, next_run))
    assert now < next_run
