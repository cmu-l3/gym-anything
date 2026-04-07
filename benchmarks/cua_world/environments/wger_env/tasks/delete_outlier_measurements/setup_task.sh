#!/bin/bash
# Task setup: delete_outlier_measurements
# Injects two specific outlier measurement entries and launches the browser to the measurements page.

echo "=== Setting up delete_outlier_measurements task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

# Inject the two specific outlier measurements using Django shell
echo "Injecting outlier measurement data..."
django_shell "
import datetime
from wger.measurements.models import Category, Measurement
from django.contrib.auth.models import User

try:
    admin = User.objects.get(username='admin')
    today = datetime.date.today()
    typo_date = today - datetime.timedelta(days=3)
    
    # Get categories
    bf_cat = Category.objects.get(name='Body Fat', user=admin)
    waist_cat = Category.objects.get(name='Waist', user=admin)
    
    # Inject 180.0 Body Fat (typo of 18.0)
    Measurement.objects.get_or_create(
        category=bf_cat, 
        date=typo_date, 
        defaults={'value': 180.0}
    )
    
    # Inject 820.0 Waist (typo of 82.0)
    Measurement.objects.get_or_create(
        category=waist_cat, 
        date=typo_date, 
        defaults={'value': 820.0}
    )
    
    print('Successfully injected outliers')
except Exception as e:
    print(f'Error injecting outliers: {e}')
"

# Give the DB a moment to settle
sleep 2

# Launch Firefox (handles cold start + snap permissions) directly to measurements
launch_firefox_to "http://localhost/en/measurement/overview/" 5

# Take a starting screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete: delete_outlier_measurements ==="