#!/bin/bash
echo "=== Setting up configure_advanced_set_types task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be ready
wait_for_wger_page

# Create Python script to insert the exact nested data structures using Django ORM
cat > /tmp/setup_routine.py << 'PYTHON_EOF'
import datetime
from django.contrib.auth.models import User
from wger.manager.models import Routine, Day, Set, Setting
from wger.exercises.models import Exercise

try:
    admin = User.objects.get(username='admin')
    
    # Clean up any previous runs
    Routine.objects.filter(name='Hypertrophy Block', user=admin).delete()
    
    # Create Routine and Day
    routine = Routine.objects.create(name='Hypertrophy Block', user=admin, start=datetime.date.today())
    day = Day.objects.create(routine=routine, name='Legs', order=1)

    # Resolve exercises (fallback to creating dummy if sync failed)
    squat_ex = Exercise.objects.filter(name__icontains='Squat').first()
    if not squat_ex:
        squat_ex = Exercise.objects.create(name='Barbell Squat')

    leg_ext_ex = Exercise.objects.filter(name__icontains='Leg Extension').first()
    if not leg_ext_ex:
        leg_ext_ex = Exercise.objects.create(name='Leg Extension')

    # Slot 1: Barbell Squat (5 sets)
    slot1 = Set.objects.create(day=day, order=1)
    slot1.exercises.add(squat_ex)
    for i in range(5):
        # set_type 1 = Normal
        Setting.objects.create(set=slot1, exercise=squat_ex, reps=10, weight=100.0, order=i+1, set_type=1)

    # Slot 2: Leg Extension (4 sets)
    slot2 = Set.objects.create(day=day, order=2)
    slot2.exercises.add(leg_ext_ex)
    for i in range(4):
        # set_type 1 = Normal
        Setting.objects.create(set=slot2, exercise=leg_ext_ex, reps=12, weight=50.0, order=i+1, set_type=1)

    print(f"SUCCESS:{routine.id}")
except Exception as e:
    print(f"ERROR:{str(e)}")
PYTHON_EOF

# Copy to container and execute
docker cp /tmp/setup_routine.py wger-web:/tmp/setup_routine.py
ROUTINE_OUTPUT=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_routine.py').read())")

# Extract Routine ID
ROUTINE_ID=$(echo "$ROUTINE_OUTPUT" | grep "SUCCESS:" | cut -d':' -f2 | tr -d '\r')

if [ -z "$ROUTINE_ID" ]; then
    echo "Failed to set up routine. Output: $ROUTINE_OUTPUT"
    exit 1
fi

echo "Created routine with ID: $ROUTINE_ID"

# Launch Firefox directly to the created routine to save the agent navigation time
launch_firefox_to "http://localhost/en/routine/${ROUTINE_ID}/view" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="