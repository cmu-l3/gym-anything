#!/bin/bash
# Task setup: add_training_day
# Creates a "Power Training" routine via API, then navigates to its view/edit page.
# The agent will add a training day named "Chest and Triceps".

source /workspace/scripts/task_utils.sh

echo "=== Setting up add_training_day task ==="

# Ensure wger is responding
wait_for_wger_page

# Remove any pre-existing "Power Training" routine to ensure clean state
docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
Routine.objects.filter(name='Power Training', user__username='admin').delete()
print('Cleaned up existing Power Training routines')
" 2>/dev/null || true

sleep 1

# Create "Power Training" routine via API (start/end required by wger)
ROUTINE_ID=$(create_routine "Power Training" "Strength and power focused training")

if [ -z "$ROUTINE_ID" ]; then
    echo "ERROR: Failed to create Power Training routine"
    exit 1
fi

echo "Created Power Training routine with ID: $ROUTINE_ID"

# Store routine ID for reference
echo "$ROUTINE_ID" > /tmp/power_training_routine_id.txt

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/routine/${ROUTINE_ID}/view" 5

# Take a starting screenshot
take_screenshot /tmp/task_add_training_day_start.png

echo "=== Task setup complete: add_training_day (routine ID: $ROUTINE_ID) ==="
