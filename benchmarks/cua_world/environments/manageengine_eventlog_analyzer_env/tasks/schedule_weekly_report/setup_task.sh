#!/bin/bash
# Setup for schedule_weekly_report task
echo "=== Setting up Schedule Weekly Report task ==="

# Source shared utilities
# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Wait for EventLog Analyzer to be fully ready
wait_for_eventlog_analyzer 900

# Record initial scheduled report count
# We check multiple likely table names since schema versions vary
echo "Recording initial scheduled report count..."
INITIAL_COUNT_1=$(ela_db_query "SELECT COUNT(*) FROM scheduledreports;" 2>/dev/null || echo "0")
INITIAL_COUNT_2=$(ela_db_query "SELECT COUNT(*) FROM task_schedule WHERE task_type ILIKE '%report%';" 2>/dev/null || echo "0")

# Save the maximum of the counts found to handle different schema versions
if [ "$INITIAL_COUNT_1" -gt "$INITIAL_COUNT_2" ]; then
    echo "$INITIAL_COUNT_1" > /tmp/initial_scheduled_count.txt
else
    echo "$INITIAL_COUNT_2" > /tmp/initial_scheduled_count.txt
fi

echo "Initial counts: scheduledreports=$INITIAL_COUNT_1, task_schedule=$INITIAL_COUNT_2"

# Launch Firefox on the Dashboard (agent must navigate to Reports)
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Focus Firefox and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    maximize_window "$WID"
fi

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="