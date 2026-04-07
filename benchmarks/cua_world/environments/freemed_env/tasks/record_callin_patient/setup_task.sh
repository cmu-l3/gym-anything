#!/bin/bash
# Setup task: record_callin_patient

echo "=== Setting up record_callin_patient task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
START_TIME=$(date +%s)
echo "$START_TIME" > /tmp/task_start_timestamp

# Ensure no pre-existing records for 'Margaret Whitfield' exist in callin or patient tables
freemed_query "DELETE FROM callin WHERE cifname LIKE '%Margaret%' AND cilname LIKE '%Whitfield%'" 2>/dev/null || true
freemed_query "DELETE FROM patient WHERE ptfname LIKE '%Margaret%' AND ptlname LIKE '%Whitfield%'" 2>/dev/null || true

# Record initial counts to verify new records are created
CALLIN_COUNT=$(freemed_query "SELECT COUNT(*) FROM callin" 2>/dev/null || echo "0")
PATIENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM patient" 2>/dev/null || echo "0")

# Save initial state securely using Python
python3 -c "
import json
with open('/tmp/initial_counts.json', 'w') as f:
    json.dump({
        'callin': int('$CALLIN_COUNT'),
        'patient': int('$PATIENT_COUNT'),
        'start_time': int('$START_TIME')
    }, f)
"

# Start FreeMED in Firefox
ensure_firefox_running "http://localhost/freemed/"

# Maximize and focus the browser window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take an initial screenshot as baseline evidence
take_screenshot /tmp/task_callin_start.png

echo ""
echo "=== Setup complete ==="
echo "Task: Record Call-In Patient entry for Margaret Whitfield."
echo "Login: admin / admin"
echo ""