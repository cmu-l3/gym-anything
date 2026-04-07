#!/bin/bash
set -e
echo "=== Exporting replace_routine_exercise result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Write a Python script to extract the exact final state of the routine
cat > /tmp/export_routine.py << 'EOF'
import json
from wger.manager.models import Routine, Day, Set, Setting
from django.contrib.auth.models import User

admin = User.objects.get(username='admin')
result = {
    'routine_found': False,
    'day_found': False,
    'exercises': [],
    'error': None
}

try:
    r = Routine.objects.filter(name='Push-Pull-Legs', user=admin).first()
    if r:
        result['routine_found'] = True
        d = Day.objects.filter(routine=r, name='Push Day').first()
        if d:
            result['day_found'] = True
            sets = Set.objects.filter(day=d)
            
            for s in sets:
                settings = Setting.objects.filter(set=s)
                
                # In wger, settings dictate the actual sets/reps
                set_count = 0
                rep_count = 0
                
                if settings.exists():
                    # Usually 1 setting object defines sets and reps
                    set_count = sum([st.sets for st in settings if st.sets])
                    # Just grab the reps from the first setting block
                    rep_count = settings[0].reps if settings[0].reps else 0
                    try:
                        rep_count = int(rep_count)
                    except ValueError:
                        rep_count = 0
                
                ex_name = s.exercise.name if s.exercise else ''
                
                result['exercises'].append({
                    'name': ex_name,
                    'sets': set_count,
                    'reps': rep_count
                })

except Exception as e:
    result['error'] = str(e)

with open('/tmp/routine_export.json', 'w') as f:
    json.dump(result, f)
EOF

# Execute extraction script in the container
docker cp /tmp/export_routine.py wger-web:/tmp/export_routine.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_routine.py').read())"

# Copy the exported JSON out of the container to the host temp directory
rm -f /tmp/task_result.json
docker cp wger-web:/tmp/routine_export.json /tmp/task_result.json

# Ensure permissions allow the verifier to read it
chmod 666 /tmp/task_result.json

echo "Result JSON extracted successfully."
cat /tmp/task_result.json
echo "=== Export complete ==="