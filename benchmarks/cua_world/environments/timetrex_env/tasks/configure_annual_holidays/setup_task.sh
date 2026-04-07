#!/bin/bash
echo "=== Setting up Configure Annual Holidays task ==="

# Source shared utilities safely
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions in case task_utils.sh is unavailable
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

# Ensure TimeTrex Docker containers are running
ensure_docker_containers

# Clean up any pre-existing matching holidays for 2026 to prevent false positives
echo "Cleaning up pre-existing 2026 holidays..."
docker exec timetrex-postgres psql -U timetrex -d timetrex -c "UPDATE holiday SET deleted=1 WHERE name IN ('Memorial Day', 'Independence Day', 'Labor Day', 'Thanksgiving Day') AND date_stamp >= '2026-01-01' AND date_stamp <= '2026-12-31';" 2>/dev/null || true

# Record initial holiday IDs (Anti-gaming check to ensure agent creates NEW records)
INITIAL_HOLIDAYS=$(docker exec timetrex-postgres psql -U timetrex -d timetrex -t -A -c "SELECT COALESCE(json_agg(id), '[]'::json) FROM holiday WHERE deleted=0;" 2>/dev/null)
if [ -z "$INITIAL_HOLIDAYS" ]; then
    INITIAL_HOLIDAYS="[]"
fi
echo "$INITIAL_HOLIDAYS" > /tmp/initial_holiday_ids.json
echo "Initial holiday IDs recorded."

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# Ensure TimeTrex is open in Firefox
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|timetrex"; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
    sleep 8
fi

# Maximize Firefox Window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="