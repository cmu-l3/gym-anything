#!/bin/bash
# Task setup: periodized_team_training
# Cleans up any pre-existing routines matching the three phase names,
# records baseline counts, and launches Firefox to the routine overview page.

source /workspace/scripts/task_utils.sh

# Make the export script executable (Lesson 120)
chmod +x /workspace/tasks/periodized_team_training/export_result.sh

echo "=== Setting up periodized_team_training task ==="

# Ensure wger is responding
wait_for_wger_page

# ---------------------------------------------------------------
# 1. Delete any pre-existing routines with the target phase names
# ---------------------------------------------------------------
echo "  Cleaning up previous task artifacts..."

docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
names = [
    'Phase 1 - Anatomical Adaptation',
    'Phase 2 - Maximal Strength',
    'Phase 3 - Power Development',
]
for name in names:
    deleted = Routine.objects.filter(name=name, user__username='admin').delete()
    print(f'Deleted routines matching \"{name}\": {deleted}')
" 2>/dev/null || true

sleep 1

# ---------------------------------------------------------------
# 2. Record baseline state
# ---------------------------------------------------------------
echo "  Recording baseline state..."

INITIAL_ROUTINE_COUNT=$(db_query "SELECT COUNT(*) FROM manager_routine WHERE user_id = (SELECT id FROM auth_user WHERE username='admin')" | tr -d '[:space:]')
INITIAL_DAY_COUNT=$(db_query "SELECT COUNT(*) FROM manager_day WHERE routine_id IN (SELECT id FROM manager_routine WHERE user_id = (SELECT id FROM auth_user WHERE username='admin'))" | tr -d '[:space:]')

# Handle empty results
INITIAL_ROUTINE_COUNT="${INITIAL_ROUTINE_COUNT:-0}"
INITIAL_DAY_COUNT="${INITIAL_DAY_COUNT:-0}"

cat > /tmp/periodized_training_initial.json << JSONEOF
{
  "initial_routine_count": ${INITIAL_ROUTINE_COUNT},
  "initial_day_count": ${INITIAL_DAY_COUNT}
}
JSONEOF

echo "  Initial routine count: ${INITIAL_ROUTINE_COUNT}"
echo "  Initial day count: ${INITIAL_DAY_COUNT}"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ---------------------------------------------------------------
# 3. Launch Firefox to the routine overview page
# ---------------------------------------------------------------
launch_firefox_to "http://localhost/en/routine/overview" 5

# Take a starting screenshot
take_screenshot /tmp/task_periodized_team_training_start.png

echo "=== Task setup complete: periodized_team_training ==="
