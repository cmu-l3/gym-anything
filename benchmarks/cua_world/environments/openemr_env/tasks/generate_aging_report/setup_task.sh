#!/bin/bash
# Setup script for Generate Aging Report Task

echo "=== Setting up Generate Aging Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
date -Iseconds > /tmp/task_start_iso.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Verify OpenEMR containers are running
echo "Verifying OpenEMR containers..."
cd /home/ga/openemr
if ! docker-compose ps | grep -q "Up"; then
    echo "Starting OpenEMR containers..."
    docker-compose up -d
    sleep 10
fi

# Wait for OpenEMR to be ready
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"
echo "Waiting for OpenEMR to be ready..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$OPENEMR_URL" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "OpenEMR is ready (HTTP $HTTP_CODE)"
        break
    fi
    sleep 2
done

# Ensure some billing data exists for the report to show
# Add sample billing entries if they don't exist
echo "Ensuring billing data exists for report..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
-- Insert billing records with various aging dates if table is mostly empty
INSERT IGNORE INTO ar_activity (pid, encounter, sequence_no, code, payer_type, post_time, post_user, pay_amount, account_code)
SELECT 
    pd.pid,
    COALESCE((SELECT MAX(id) FROM form_encounter WHERE pid = pd.pid), 1),
    1,
    '99213',
    0,
    DATE_SUB(NOW(), INTERVAL (30 * (pd.pid % 5)) DAY),
    1,
    0,
    'CO'
FROM patient_data pd
WHERE pd.pid <= 5
ON DUPLICATE KEY UPDATE post_time = post_time;
" 2>/dev/null || echo "Note: Billing data setup skipped or already exists"

# Record initial state - check if any reports have been accessed
echo "Recording initial state..."
INITIAL_LOG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM log WHERE event LIKE '%report%' OR comments LIKE '%report%'" 2>/dev/null || echo "0")
echo "$INITIAL_LOG_COUNT" > /tmp/initial_report_log_count.txt
echo "Initial report log entries: $INITIAL_LOG_COUNT"

# Kill any existing Firefox instances for clean start
echo "Preparing Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox with OpenEMR login page
echo "Launching Firefox with OpenEMR login page..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window to appear
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openemr"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Focusing Firefox window: $WID"
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Generate Aging Report Task Setup Complete ==="
echo ""
echo "TASK: Generate Accounts Receivable Aging Report"
echo "================================================"
echo ""
echo "Login credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR"
echo "  2. Navigate to Reports menu"
echo "  3. Find Collections Report or Patient Aging under Billing reports"
echo "  4. Generate the report to view patient balances by aging period"
echo ""
echo "The report should show aging columns: 0-30, 31-60, 61-90, 91-120, 120+ days"
echo ""