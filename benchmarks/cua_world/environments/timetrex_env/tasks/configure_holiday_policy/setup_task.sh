#!/bin/bash
# Setup script for Configure Holiday Policy task
# Records initial state and cleans up specific target entities

echo "=== Setting up Configure Holiday Policy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if task_utils.sh is missing
if ! type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers() {
        docker ps | grep -q timetrex || docker start timetrex timetrex-postgres 2>/dev/null || true
        sleep 3
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "$1" 2>/dev/null
    }
fi

# Run pre-flight check
ensure_docker_containers

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

# Record task start time (UNIX epoch) for anti-gaming verification
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start timestamp: $TASK_START"

# Clean up any pre-existing objects matching our targets to ensure a clean slate
echo "Cleaning up any pre-existing target records..."

# Delete associations for the target policy
timetrex_query "
DELETE FROM holiday_policy_recurring_holiday 
WHERE holiday_policy_id IN (SELECT id FROM holiday_policy WHERE name = '2026 Standard Holidays');"

# Delete the target policy
timetrex_query "
DELETE FROM holiday_policy WHERE name = '2026 Standard Holidays';"

# Delete target recurring holidays
timetrex_query "
DELETE FROM recurring_holiday 
WHERE name IN ('New Year''s Day', 'New Years Day', 'Independence Day', 'Christmas Day');"

# Record initial counts
INITIAL_RH_COUNT=$(timetrex_query "SELECT COUNT(*) FROM recurring_holiday WHERE deleted=0;" 2>/dev/null || echo "0")
INITIAL_HP_COUNT=$(timetrex_query "SELECT COUNT(*) FROM holiday_policy WHERE deleted=0;" 2>/dev/null || echo "0")

echo "$INITIAL_RH_COUNT" > /tmp/initial_rh_count.txt
echo "$INITIAL_HP_COUNT" > /tmp/initial_hp_count.txt
echo "Initial Recurring Holiday count: $INITIAL_RH_COUNT"
echo "Initial Holiday Policy count: $INITIAL_HP_COUNT"

# Ensure Firefox is open and focused on TimeTrex
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|timetrex\|mozilla"; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
    sleep 8
fi

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo "=== Task Setup Complete ==="