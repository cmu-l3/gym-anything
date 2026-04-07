#!/bin/bash
set -e
echo "=== Setting up extract_exercise_pr task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

# Write Python seed script to generate realistic workout logs with a random max weight
cat > /tmp/wger_pr_seed.py << 'PYTHON_SEED_EOF'
import datetime
import random
import traceback
from django.contrib.auth.models import User
from wger.exercises.models import Exercise, ExerciseCategory, Language
from wger.manager.models import WorkoutLog

try:
    admin = User.objects.get(username='admin')
    cat, _ = ExerciseCategory.objects.get_or_create(name='Legs')
    lang, _ = Language.objects.get_or_create(short_name='en', defaults={'full_name': 'English'})
    
    ex, _ = Exercise.objects.get_or_create(
        name='Competition Barbell Squat',
        defaults={'category': cat, 'user': admin, 'language': lang, 'description': 'Deep barbell squat.'}
    )
    
    # Clear old logs for this exercise just in case of environment reuse
    WorkoutLog.objects.filter(exercise=ex).delete()

    # Generate a randomized PR weight
    pr_weights = [120.0, 122.5, 125.0, 127.5, 130.0, 132.5, 135.0, 140.0, 142.5]
    pr_weight = random.choice(pr_weights)
    
    # Save ground truth to a file inside container to extract later
    with open('/tmp/pr_ground_truth.txt', 'w') as f:
        f.write(str(pr_weight))

    # Generate 10 workout sessions peaking at the PR weight
    today = datetime.date.today()
    weights = [
        pr_weight - 20, 
        pr_weight - 15, 
        pr_weight - 10, 
        pr_weight - 5, 
        pr_weight,           # The PR!
        pr_weight - 2.5, 
        pr_weight - 7.5, 
        pr_weight - 12.5, 
        pr_weight - 10, 
        pr_weight - 15
    ]

    for i, w in enumerate(weights):
        d = today - datetime.timedelta(days=(10-i)*7)
        WorkoutLog.objects.create(
            user=admin,
            exercise=ex,
            weight=w,
            reps=5,
            date=d
        )
    print("SEED_SUCCESS")
except Exception as e:
    traceback.print_exc()
    print("SEED_ERROR")
PYTHON_SEED_EOF

# Copy and execute the seed script inside the wger-web container
docker cp /tmp/wger_pr_seed.py wger-web:/tmp/wger_pr_seed.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_pr_seed.py').read())"

# Extract the ground truth and store it securely on the host
docker exec wger-web cat /tmp/pr_ground_truth.txt > /tmp/.pr_truth
chmod 600 /tmp/.pr_truth

# Ensure target directory exists for the agent
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Launch Firefox directly to the exercise overview page to start the task
launch_firefox_to "http://localhost/en/exercise/overview/" 5

# Take initial screenshot showing starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="