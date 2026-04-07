#!/bin/bash
set -e

echo "=== Setting up reorder_workout_exercises task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

# Create the Python script to setup the routine and exercises
cat > /tmp/wger_setup_routine.py << 'EOF'
import json
import sys

from django.contrib.auth.models import User
from wger.manager.models import Routine, Day, Set, Setting
from wger.exercises.models import Exercise, Language

try:
    admin = User.objects.get(username='admin')
    
    # Clean up any existing routine with this name for clean state
    Routine.objects.filter(name='Strength & Size Phase 1', user=admin).delete()

    routine = Routine.objects.create(
        name='Strength & Size Phase 1', 
        user=admin, 
        description='Focus on hypertrophy and base strength'
    )
    day = Day.objects.create(
        routine=routine, 
        name='Lower Body Focus', 
        description='Leg day'
    )

    def get_or_create_ex(name_query, exact_name):
        ex = Exercise.objects.filter(name__icontains=name_query).first()
        if not ex:
            ex = Exercise.objects.create(name=exact_name)
        return ex

    # Find or create the exercises
    ex_squat = get_or_create_ex('Squat', 'Squat')
    ex_legext = get_or_create_ex('Leg Extension', 'Leg Extension')
    ex_calf = get_or_create_ex('Calf Raise', 'Standing Calf Raises')

    # Create sets in the WRONG order (Calf -> Leg Ext -> Squat)
    
    # 1. Calf Raises (order 1)
    set1 = Set.objects.create(day=day, order=1)
    Setting.objects.create(set=set1, exercise=ex_calf, sets=3, reps='12')

    # 2. Leg Extension (order 2)
    set2 = Set.objects.create(day=day, order=2)
    Setting.objects.create(set=set2, exercise=ex_legext, sets=3, reps='12')

    # 3. Squat (order 3)
    set3 = Set.objects.create(day=day, order=3)
    Setting.objects.create(set=set3, exercise=ex_squat, sets=4, reps='5')

    out = {
        'routine_id': routine.id,
        'day_id': day.id,
        'id_calf': set1.id,
        'id_legext': set2.id,
        'id_squat': set3.id
    }
    
    print("JSON_START")
    print(json.dumps(out))
    print("JSON_END")

except Exception as e:
    print("JSON_START")
    print(json.dumps({"error": str(e)}))
    print("JSON_END")
    sys.exit(1)
EOF

echo "Executing setup script inside wger container..."
docker cp /tmp/wger_setup_routine.py wger-web:/tmp/wger_setup_routine.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_setup_routine.py').read())" > /tmp/setup_out.txt

# Extract JSON data
sed -n '/JSON_START/,/JSON_END/p' /tmp/setup_out.txt | grep -v 'JSON_START' | grep -v 'JSON_END' > /tmp/wger_task_info.json

# Verify setup succeeded
if grep -q "error" /tmp/wger_task_info.json; then
    echo "ERROR: Failed to setup routine. See /tmp/wger_task_info.json"
    cat /tmp/wger_task_info.json
    exit 1
fi

echo "Task data created successfully:"
cat /tmp/wger_task_info.json

# Launch Firefox to the Routines overview page (forcing navigation)
launch_firefox_to "http://localhost/en/routine/overview/" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="