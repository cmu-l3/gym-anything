#!/bin/bash
echo "=== Exporting edit_measurement_entry result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Extract final state from database via Django ORM
cat << 'PYTHON_EOF' > /tmp/export_state.py
import json
from django.contrib.auth.models import User
from wger.measurements.models import Category, Measurement

admin = User.objects.get(username='admin')

all_measurements = list(Measurement.objects.filter(category__user=admin).values('id', 'value', 'category__name'))
categories_count = Category.objects.filter(user=admin).count()

state = {
    'categories_count': categories_count,
    'all_measurements': [
        {'id': m['id'], 'value': float(m['value']), 'category': m['category__name']} 
        for m in all_measurements
    ]
}

with open('/tmp/state_out.json', 'w') as f:
    json.dump(state, f)
PYTHON_EOF

docker cp /tmp/export_state.py wger-web:/tmp/export_state.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_state.py').read())"

# Copy the generated state out
docker cp wger-web:/tmp/state_out.json /tmp/current_state.json

# Merge initial and current states into a single result file
python3 -c "
import json, time
try:
    with open('/tmp/initial_state.json') as f: initial = json.load(f)
except:
    initial = {}

try:
    with open('/tmp/current_state.json') as f: current = json.load(f)
except:
    current = {}

try:
    with open('/tmp/task_start_time.txt') as f: start_time = int(f.read().strip())
except:
    start_time = 0

result = {
    'initial': initial,
    'current': current,
    'task_start': start_time,
    'task_end': int(time.time()),
    'screenshot_path': '/tmp/task_final_state.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="