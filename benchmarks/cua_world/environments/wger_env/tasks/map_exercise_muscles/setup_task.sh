#!/bin/bash
set -e
echo "=== Setting up map_exercise_muscles task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming measures
date +%s > /tmp/task_start_time.txt

# Ensure wger web service is running and responsive
wait_for_wger_page

# -----------------------------------------------------------------------
# Inject the custom exercise WITHOUT any mapped muscles
# -----------------------------------------------------------------------
cat > /tmp/setup_exercise.py << 'EOF'
import sys
from wger.exercises.models import Exercise, ExerciseCategory, Language

try:
    # Safely get language and category defaults
    lang = Language.objects.filter(short_name='en').first()
    if not lang:
        lang = Language.objects.first()
        
    cat = ExerciseCategory.objects.filter(name__icontains='Leg').first()
    if not cat:
        cat = ExerciseCategory.objects.first()

    # Create the target exercise
    ex, created = Exercise.objects.get_or_create(
        name='Landmine Reverse Lunge',
        defaults={
            'language': lang,
            'category': cat,
            'description': 'A great unilateral leg exercise.'
        }
    )
    
    # Ensure no muscles are mapped initially
    ex.muscles.clear()
    ex.muscles_secondary.clear()
    
    # Output the ID with a specific prefix so we can grep it reliably
    print(f"EXERCISE_ID:{ex.id}")
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
EOF

docker cp /tmp/setup_exercise.py wger-web:/tmp/setup_exercise.py
RAW_OUT=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_exercise.py').read())")

# Extract only the exact ID string
EXERCISE_ID=$(echo "$RAW_OUT" | grep 'EXERCISE_ID:' | cut -d':' -f2 | tr -d ' \r\n')

if [ -z "$EXERCISE_ID" ]; then
    echo "WARNING: Failed to extract Exercise ID. Setting to fallback value -1."
    EXERCISE_ID="-1"
fi

echo "$EXERCISE_ID" > /tmp/initial_exercise_id.txt
echo "Created target exercise with ID: $EXERCISE_ID"

# -----------------------------------------------------------------------
# Browser Setup
# -----------------------------------------------------------------------
# Launch Firefox directly to the exercise overview (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/exercise/overview/" 5

# Take initial screenshot to prove starting state
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="