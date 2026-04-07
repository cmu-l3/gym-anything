#!/bin/bash
echo "=== Setting up populate_workout_day task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for wger web service to be accessible
wait_for_wger_page

# Ensure clean state: delete any pre-existing routine with this name to avoid ambiguity
docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
Routine.objects.filter(name='Mechanic Strength Program').delete()
" 2>/dev/null || true

# Create Routine via API utility
ROUTINE_ID=$(create_routine "Mechanic Strength Program" "Upper body focus for mechanics")
if [ -z "$ROUTINE_ID" ]; then
    echo "ERROR: Failed to create routine via API"
    exit 1
fi
echo "$ROUTINE_ID" > /tmp/routine_id.txt

# Create empty Day via API utility
DAY_ID=$(create_day "$ROUTINE_ID" "Upper Body Day" 1)
echo "$DAY_ID" > /tmp/day_id.txt

# Launch Firefox and navigate directly to the routine's view page
launch_firefox_to "http://localhost/en/routine/${ROUTINE_ID}/view" 5

# Ensure window is maximized for the agent
maximize_firefox

# Take initial state screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Routine ID: $ROUTINE_ID"
echo "Day ID: $DAY_ID"