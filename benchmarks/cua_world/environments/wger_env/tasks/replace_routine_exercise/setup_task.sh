#!/bin/bash
set -e
echo "=== Setting up replace_routine_exercise task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be ready
wait_for_wger_page

# Write a Python script to seed the exact starting routine structure in the DB
cat > /tmp/setup_routine.py << 'EOF'
import datetime
from django.contrib.auth.models import User
from wger.manager.models import Routine, Day, Set, Setting
from wger.exercises.models import Exercise

try:
    admin = User.objects.get(username='admin')
    
    # Clean up any existing routine with this name to ensure clean state
    Routine.objects.filter(name='Push-Pull-Legs', user=admin).delete()
    
    # Create Routine and Day
    r = Routine.objects.create(
        name='Push-Pull-Legs', 
        user=admin, 
        description='Standard PPL split', 
        start=datetime.date.today()
    )
    d = Day.objects.create(routine=r, name='Push Day', description='Push focused training')
    
    # Helper to get or create exercises (acts as a safety net if sync missed them)
    def get_or_create_ex(search_name):
        ex = Exercise.objects.filter(name__icontains=search_name).first()
        if not ex:
            ex = Exercise.objects.create(name=search_name)
        return ex

    # Ensure all required exercises exist in the database
    bench = get_or_create_ex('Bench Press')
    ohp = get_or_create_ex('Overhead Press')
    triceps = get_or_create_ex('Triceps Extension')
    
    # Also ensure Lateral Raise exists so the agent can find it when adding
    get_or_create_ex('Lateral Raise')
    
    # Add exercises to the day
    set_bench = Set.objects.create(day=d, exercise=bench, order=1)
    Setting.objects.create(set=set_bench, sets=4, reps=8)
    
    set_ohp = Set.objects.create(day=d, exercise=ohp, order=2)
    Setting.objects.create(set=set_ohp, sets=3, reps=10)
    
    set_tri = Set.objects.create(day=d, exercise=triceps, order=3)
    Setting.objects.create(set=set_tri, sets=3, reps=12)
    
    print(f"SUCCESS: Created Routine ID {r.id}")

except Exception as e:
    import traceback
    print(f"ERROR setting up routine: {e}")
    traceback.print_exc()
EOF

# Copy the script to the web container and execute it
docker cp /tmp/setup_routine.py wger-web:/tmp/setup_routine.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_routine.py').read())"

# Launch Firefox directly to the routines overview page
launch_firefox_to "http://localhost/en/routine/overview/" 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="