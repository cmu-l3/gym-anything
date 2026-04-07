#!/bin/bash
# Task setup: create_custom_exercise

echo "=== Setting up create_custom_exercise task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

# Clean up any existing "Sled Push" exercises to ensure a clean slate
echo "Cleaning up any pre-existing 'Sled Push' exercises..."
cat > /tmp/clean_ex.py << 'EOF'
from wger.exercises.models import Exercise
try:
    count, _ = Exercise.objects.filter(name__icontains="Sled Push").delete()
    print(f"Deleted {count} pre-existing exercises.")
except Exception as e:
    print(f"Cleanup error: {e}")
EOF
docker cp /tmp/clean_ex.py wger-web:/tmp/clean_ex.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/clean_ex.py').read())"

# Launch Firefox (handles cold start + snap permissions)
echo "Launching Firefox to wger exercise overview..."
launch_firefox_to "http://localhost/en/exercise/overview/" 5

# Take a starting screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete: create_custom_exercise ==="