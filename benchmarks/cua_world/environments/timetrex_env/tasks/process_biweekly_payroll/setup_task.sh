#!/bin/bash
# Setup script for Process Bi-Weekly Payroll task
# Records initial state before the task begins

echo "=== Setting up Process Bi-Weekly Payroll task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions in case task_utils.sh is missing
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    }
fi

if ! type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers() {
        if ! docker ps | grep -q timetrex-postgres; then
            echo "Starting TimeTrex containers..."
            docker start timetrex-postgres timetrex-app 2>/dev/null || true
            sleep 10
        fi
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Ensure services are up
ensure_docker_containers

# Record task start timestamp (Epoch time matches TimeTrex's internal storage format)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp (Epoch): $TASK_START"

# Record initial pay stub count (anti-gaming: agent must generate NEW pay stubs)
INITIAL_COUNT=$(timetrex_query "SELECT COUNT(*) FROM pay_stub" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_pay_stub_count
echo "Initial pay stub count: $INITIAL_COUNT"

# Verify that there is at least one "Open" Bi-Weekly pay period to process
OPEN_BW=$(timetrex_query "
    SELECT COUNT(*) 
    FROM pay_period pp 
    JOIN pay_period_schedule pps ON pp.pay_period_schedule_id = pps.id 
    WHERE pp.status_id = 10 AND pps.name LIKE '%Bi-Weekly%';
" 2>/dev/null || echo "0")

if [ "$OPEN_BW" -eq "0" ]; then
    echo "WARNING: No Open Bi-Weekly pay periods found in database."
    echo "The demo data generator might have failed to create them."
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Task Setup Complete ==="
echo "Task: Process an Open 'Bi-Weekly' pay period."
echo "Navigate to Payroll -> Pay Periods, locate an open Bi-Weekly period, and click Process."
echo "Login credentials: demoadmin1 / demo"
echo ""