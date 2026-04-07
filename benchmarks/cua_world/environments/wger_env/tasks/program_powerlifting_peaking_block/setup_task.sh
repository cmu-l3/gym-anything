#!/bin/bash
# setup_task.sh — Prepare wger environment for routine creation
set -e

echo "=== Setting up program_powerlifting_peaking_block task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Wait for wger web service to be fully responsive
wait_for_wger_page

# 3. Clean up any existing attempts at this routine to ensure clean slate
echo "Cleaning up any existing Smolov routines..."
docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
Routine.objects.filter(name__icontains='Smolov').delete()
print('Cleanup complete')
" 2>/dev/null || true

# 4. Start Firefox and navigate to the routines dashboard
echo "Launching Firefox..."
launch_firefox_to "http://localhost/en/routine/overview" 5

# 5. Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="