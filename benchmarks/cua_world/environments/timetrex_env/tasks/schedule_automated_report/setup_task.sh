#!/bin/bash
# Setup script for Schedule Automated Report task
# Records initial state before the task begins

echo "=== Setting up Schedule Automated Report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Define timetrex_query fallback if not loaded
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | tr -d '\n\r '
    }
fi

# Run pre-flight check (BLOCKS until environment is ready)
if type preflight_check &>/dev/null; then
    if ! preflight_check; then
        echo "FATAL: Pre-flight check failed. Cannot start task."
        exit 1
    fi
else
    # Fallback initialization
    docker ps | grep -q timetrex || docker start timetrex timetrex-postgres 2>/dev/null || true
    sleep 5
fi

# Take initial screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial_screenshot.png
else
    DISPLAY=:1 import -window root /tmp/task_initial_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || true
fi

# Record initial report schedule count
INITIAL_COUNT=$(timetrex_query "SELECT COUNT(*) FROM report_schedule WHERE deleted=0")
if [ -z "$INITIAL_COUNT" ]; then
    INITIAL_COUNT="0"
fi
echo "$INITIAL_COUNT" > /tmp/initial_report_count
echo "Initial report schedule count: $INITIAL_COUNT"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Final verification - ensure we can see the login page
if type verify_timetrex_accessible &>/dev/null; then
    if ! verify_timetrex_accessible; then
        echo "FATAL: TimeTrex login page not accessible at task start!"
        exit 1
    fi
else
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/interface/Login.php)
    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
        echo "FATAL: TimeTrex login page returned HTTP $HTTP_CODE"
        exit 1
    fi
fi

echo ""
echo "=== Task Setup Complete ==="
echo "Task: Schedule an automated report in TimeTrex"
echo "Name: Weekly Overtime Review"
echo "Report: Timesheet Summary"
echo "To Email: supervisor@greenleafwellness.com"
echo "Frequency: Weekly"
echo "Login credentials: demoadmin1 / demo"
echo ""