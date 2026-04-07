#!/bin/bash
set -e

echo "=== Setting up reclassify_exercises_to_custom_category task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

# Clean up any previous runs and record initial category count inside container
cat > /tmp/wger_init_check.py << 'EOF'
import json
from wger.exercises.models import ExerciseCategory

# Clean up any prior 'Powerlifting Lifts' categories from testing
ExerciseCategory.objects.filter(name='Powerlifting Lifts').delete()

# Record initial count for anti-gaming verification
with open('/tmp/init_state.json', 'w') as f:
    json.dump({"initial_category_count": ExerciseCategory.objects.count()}, f)
EOF

echo "Executing initial state check in wger container..."
docker cp /tmp/wger_init_check.py wger-web:/tmp/wger_init_check.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_init_check.py').read())"

# Retrieve the initial state
docker cp wger-web:/tmp/init_state.json /tmp/initial_state.json
chmod 666 /tmp/initial_state.json

echo "Initial state recorded:"
cat /tmp/initial_state.json
echo ""

# Launch Firefox directly to wger dashboard (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/dashboard/" 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="