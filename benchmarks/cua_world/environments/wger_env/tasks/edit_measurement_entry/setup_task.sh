#!/bin/bash
echo "=== Setting up edit_measurement_entry task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure wger is up and responding
wait_for_wger_page

echo "Resetting Waist measurement data to deterministic initial state..."
# Write a Python script to extract and reset state directly via Django ORM
cat << 'PYTHON_EOF' > /tmp/extract_state.py
import json, datetime
from django.contrib.auth.models import User
from wger.measurements.models import Category, Measurement

admin = User.objects.get(username='admin')
today = datetime.date.today()

# Get or create Waist category
waist_cat, _ = Category.objects.get_or_create(name='Waist', user=admin, defaults={'unit': 'cm'})

# Clear existing Waist entries to ensure clean initial state for the test
Measurement.objects.filter(category=waist_cat).delete()

# Re-create exactly 5 Waist entries
for i in range(5):
    d = today - datetime.timedelta(days=i * 7)
    val = round(82.0 - i * 0.2, 1)
    Measurement.objects.create(category=waist_cat, date=d, value=val)

# Identify the target entry (most recent, value 82.0)
target = Measurement.objects.filter(category=waist_cat).order_by('-date').first()

# Dump all measurements to capture global initial state
all_measurements = list(Measurement.objects.filter(category__user=admin).values('id', 'value', 'category__name'))

state = {
    'target_id': target.id,
    'waist_cat_id': waist_cat.id,
    'all_measurements': [
        {'id': m['id'], 'value': float(m['value']), 'category': m['category__name']} 
        for m in all_measurements
    ]
}

with open('/tmp/state_out.json', 'w') as f:
    json.dump(state, f)
PYTHON_EOF

# Execute the script inside the container
docker cp /tmp/extract_state.py wger-web:/tmp/extract_state.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/extract_state.py').read())"

# Copy the generated state out to the host
docker cp wger-web:/tmp/state_out.json /tmp/initial_state.json
chmod 666 /tmp/initial_state.json

# Launch Firefox and navigate to the dashboard (cold start + snap permissions)
echo "Launching Firefox to wger dashboard..."
launch_firefox_to "http://localhost/en/dashboard/" 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="