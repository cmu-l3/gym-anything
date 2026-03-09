#!/bin/bash
# Task setup: log_workout_session
# Creates a "Full Body Workout" routine via API, then navigates to the
# training calendar page so the agent can log a workout session.

source /workspace/scripts/task_utils.sh

echo "=== Setting up log_workout_session task ==="

# Ensure wger is responding
wait_for_wger_page

# Remove any pre-existing "Full Body Workout" routines to ensure clean state
docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
Routine.objects.filter(name='Full Body Workout', user__username='admin').delete()
print('Cleaned up existing Full Body Workout routines')
" 2>/dev/null || true

# Clean up ALL prior WorkoutSession objects for admin to avoid stale calendar dots
docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import WorkoutSession
from django.contrib.auth.models import User
admin = User.objects.get(username='admin')
count, _ = WorkoutSession.objects.filter(user=admin).delete()
print(f'Deleted {count} existing WorkoutSession objects')
" 2>/dev/null || true

sleep 1

# Create "Full Body Workout" routine via API (start/end required by wger)
ROUTINE_ID=$(create_routine "Full Body Workout" "Compound movements targeting all major muscle groups")

if [ -z "$ROUTINE_ID" ]; then
    echo "ERROR: Failed to create Full Body Workout routine"
    exit 1
fi

echo "Created Full Body Workout routine with ID: $ROUTINE_ID"

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/routine/calendar" 5

# Take a starting screenshot
take_screenshot /tmp/task_log_workout_session_start.png

echo "=== Task setup complete: log_workout_session ==="
