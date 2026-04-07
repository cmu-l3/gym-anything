#!/bin/bash
echo "=== Setting up program_equipment_constrained_routine task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

# Clean up any existing routine with the target name to ensure a clean slate
# This guarantees the agent must actually perform the creation during the task
echo "Cleaning up any existing target routines..."
docker exec wger-web python3 manage.py shell -c "
try:
    from wger.manager.models import Routine
    deleted, _ = Routine.objects.filter(name='Hotel Gym Full Body', user__username='admin').delete()
    print(f'Cleaned up {deleted} existing routines')
except Exception as e:
    print(f'Cleanup error (safe to ignore): {e}')
" 2>/dev/null || true

# Launch Firefox to the routine overview page
echo "Launching browser..."
launch_firefox_to "http://localhost/en/routine/overview/" 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="