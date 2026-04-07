#!/bin/bash
echo "=== Exporting configure_advanced_set_types task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Python script to extract the resulting configuration from the DB
cat > /tmp/export_routine.py << 'PYTHON_EOF'
import json
from wger.manager.models import Routine, Day, Set, Setting

result = {'exists': False, 'squat_sets': [], 'extension_sets': []}
try:
    routine = Routine.objects.filter(name='Hypertrophy Block', user__username='admin').last()
    if routine:
        result['exists'] = True
        day = Day.objects.filter(routine=routine, name='Legs').first()
        if day:
            slots = Set.objects.filter(day=day).order_by('order')
            for slot in slots:
                ex = slot.exercises.first()
                if ex:
                    # Query ordered settings to inspect the types
                    settings = Setting.objects.filter(set=slot, exercise=ex).order_by('order')
                    types = [s.set_type for s in settings]
                    if 'Squat' in ex.name:
                        result['squat_sets'] = types
                    elif 'Extension' in ex.name:
                        result['extension_sets'] = types
except Exception as e:
    result['error'] = str(e)

with open('/tmp/db_data.json', 'w') as f:
    json.dump(result, f)
PYTHON_EOF

# Execute in container and fetch results
docker cp /tmp/export_routine.py wger-web:/tmp/export_routine.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_routine.py').read())"
docker cp wger-web:/tmp/db_data.json /tmp/db_data.json

# Merge database info with task metadata
cat > /tmp/process_export.py << PYTHON_EOF
import json

try:
    with open('/tmp/db_data.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {"exists": False, "squat_sets": [], "extension_sets": []}

data["task_start"] = $TASK_START
data["task_end"] = $TASK_END
data["app_was_running"] = True

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
PYTHON_EOF

python3 /tmp/process_export.py

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo -e "\n=== Export complete ==="