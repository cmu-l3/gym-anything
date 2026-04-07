#!/bin/bash
# Setup script for Process Mileage Reimbursement task

echo "=== Setting up Process Mileage Reimbursement task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions in case task_utils.sh is missing or incomplete
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    }
fi

if ! type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers() {
        if ! docker ps | grep -q timetrex-postgres; then
            echo "Starting TimeTrex containers..."
            docker-compose -f /home/ga/timetrex/docker-compose.yml up -d 2>/dev/null || true
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

# 1. Ensure environment is running
ensure_docker_containers

# 2. Verify target employee exists
JOHN_EXISTS=$(timetrex_query "SELECT COUNT(*) FROM users WHERE first_name='John' AND last_name='Doe' AND deleted=0")
if [ "$JOHN_EXISTS" = "0" ] || [ -z "$JOHN_EXISTS" ]; then
    echo "FATAL: Employee John Doe not found in database! Demo data missing."
    exit 1
fi

# 3. Clean up any existing state to ensure task repeatability
echo "Cleaning up any pre-existing matching policies or expenses..."

# Soft-delete any existing "Mileage Reimbursement" policies
timetrex_query "UPDATE expense_policy SET deleted=1 WHERE name='Mileage Reimbursement' AND deleted=0;" >/dev/null 2>&1

# Soft-delete any 97.15 expenses for John Doe to prevent false positives from previous runs
timetrex_query "
UPDATE user_expense 
SET deleted=1 
WHERE amount=97.15 
  AND user_id=(SELECT id FROM users WHERE first_name='John' AND last_name='Doe' AND deleted=0 LIMIT 1) 
  AND deleted=0;
" >/dev/null 2>&1

# 4. Record task start parameters
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# Ensure browser is open on TimeTrex
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|timetrex\|mozilla"; then
    su - ga -c "DISPLAY=:1 firefox http://localhost/interface/Login.php >> /home/ga/firefox.log 2>&1 &"
    sleep 8
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
echo "Task: Create 'Mileage Reimbursement' Expense Policy and log a 97.15 expense for John Doe."
echo "Start timestamp: $TASK_START"