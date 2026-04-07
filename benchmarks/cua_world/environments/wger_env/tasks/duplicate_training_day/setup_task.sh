#!/bin/bash
set -e
echo "=== Setting up duplicate_training_day task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger web service to be fully responsive
wait_for_wger_page

echo "Seeding routine data..."

# Create a Python script to seed the specific routine, day, slots, and sets
cat > /tmp/wger_seed_routine.py << 'PYTHON_SEED_EOF'
import os
import sys
import django
from django.contrib.auth.models import User
from wger.manager.models import Routine, Day, Setting, Set
from wger.exercises.models import Exercise

try:
    admin = User.objects.get(username="admin")
    
    # Delete any existing routine with this name to ensure clean state
    Routine.objects.filter(name="Push-Pull-Legs Split", user=admin).delete()
    
    # Create Routine and Day
    r = Routine.objects.create(name="Push-Pull-Legs Split", user=admin, background="Symmetrical PPL split")
    d = Day.objects.create(routine=r, name="Push 1", description="First push day of the week")
    
    # Identify 3 exercises (use specific ones if available, otherwise fallback to first available)
    ex1 = Exercise.objects.filter(name__icontains="Bench Press").first()
    ex2 = Exercise.objects.filter(name__icontains="Overhead Press").first()
    ex3 = Exercise.objects.filter(name__icontains="Triceps").first()
    
    all_ex = list(Exercise.objects.all()[:5])
    if not ex1: ex1 = all_ex[0] if len(all_ex) > 0 else None
    if not ex2: ex2 = all_ex[1] if len(all_ex) > 1 else ex1
    if not ex3: ex3 = all_ex[2] if len(all_ex) > 2 else ex1
    
    if ex1 and ex2 and ex3:
        # Ex 1: 3 sets of 8
        s1 = Setting.objects.create(day=d, exercise=ex1, order=1)
        Set.objects.create(setting=s1, reps=8, order=1)
        Set.objects.create(setting=s1, reps=8, order=2)
        Set.objects.create(setting=s1, reps=8, order=3)
        
        # Ex 2: 3 sets of 10
        s2 = Setting.objects.create(day=d, exercise=ex2, order=2)
        Set.objects.create(setting=s2, reps=10, order=1)
        Set.objects.create(setting=s2, reps=10, order=2)
        Set.objects.create(setting=s2, reps=10, order=3)
        
        # Ex 3: 4 sets of 12
        s3 = Setting.objects.create(day=d, exercise=ex3, order=3)
        Set.objects.create(setting=s3, reps=12, order=1)
        Set.objects.create(setting=s3, reps=12, order=2)
        Set.objects.create(setting=s3, reps=12, order=3)
        Set.objects.create(setting=s3, reps=12, order=4)
        
        print(f"SUCCESS:{r.id}")
    else:
        print("ERROR: Not enough exercises found in database to seed task")
except Exception as e:
    import traceback
    print(f"ERROR: {e}")
    traceback.print_exc()
PYTHON_SEED_EOF

# Execute the seed script inside the wger container
docker cp /tmp/wger_seed_routine.py wger-web:/tmp/wger_seed_routine.py
SEED_OUTPUT=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_seed_routine.py').read())" 2>/dev/null)

echo "Seed output: $SEED_OUTPUT"

# Extract routine ID to navigate directly to it
ROUTINE_ID=$(echo "$SEED_OUTPUT" | grep -oP 'SUCCESS:\K\d+')

# Launch Firefox directly to the routine overview or the specific routine
if [ -n "$ROUTINE_ID" ]; then
    launch_firefox_to "http://localhost/en/routine/${ROUTINE_ID}/view" 5
else
    launch_firefox_to "http://localhost/en/routine/overview" 5
fi

# Take an initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="