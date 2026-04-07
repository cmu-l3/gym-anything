#!/bin/bash
set -e

echo "=== Setting up plate loading progression task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Generate a dynamic historical maximum weight to prevent hardcoding
# Range: 105.0 to 160.0 kg
WEIGHTS=( 105.0 112.5 120.0 125.0 132.5 140.0 145.0 152.5 160.0 )
RAND_INDEX=$((RANDOM % ${#WEIGHTS[@]}))
BASE_WEIGHT=${WEIGHTS[$RAND_INDEX]}

# Save for the verifier (hidden from agent)
echo "$BASE_WEIGHT" > /tmp/squat_base_weight.txt

echo "Injecting dynamic workout history (Max Squat: ${BASE_WEIGHT}kg)..."

# 2. Inject historical workout data via Django ORM shell
cat > /tmp/inject_log.py << PYEOF
import datetime
from django.contrib.auth.models import User
from django.apps import apps

try:
    Exercise = apps.get_model('exercises', 'Exercise')
    WorkoutSession = apps.get_model('manager', 'WorkoutSession')
    WorkoutLog = apps.get_model('manager', 'WorkoutLog')

    admin = User.objects.get(username='admin')
    
    # Ensure "Squat" exists
    squat = Exercise.objects.filter(name__icontains='Squat').first()
    if not squat:
        squat = Exercise.objects.create(name='Squat')

    # Create a workout session from 2 days ago
    session = WorkoutSession.objects.create(
        user=admin, 
        date=datetime.date.today() - datetime.timedelta(days=2)
    )
    
    # Create logs: A lighter warmup set and the dynamic heavy set
    WorkoutLog.objects.create(session=session, exercise=squat, reps=8, weight=$BASE_WEIGHT - 40.0)
    WorkoutLog.objects.create(session=session, exercise=squat, reps=5, weight=$BASE_WEIGHT)
    
    print("Successfully injected workout logs")
except Exception as e:
    print(f"Failed to inject logs: {e}")
PYEOF

# Copy script to container and execute
docker cp /tmp/inject_log.py wger-web:/tmp/inject_log.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/inject_log.py').read())"

# 3. Clean up any pre-existing output files
rm -f /home/ga/next_squat_plates.txt

# 4. Wait for application to be reachable and start Firefox
wait_for_wger_page
launch_firefox_to "http://localhost/en/workout/" 5

# 5. Capture initial proof state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="