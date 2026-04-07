#!/bin/bash
# Setup script for Add Fee Schedule Code task

echo "=== Setting up Add Fee Schedule Code Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Ensure the target code doesn't already exist (clean state)
echo "Ensuring clean state - removing any existing 99441 code..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
DELETE FROM prices WHERE pr_id IN (SELECT id FROM codes WHERE code = '99441');
DELETE FROM codes WHERE code = '99441';
" 2>/dev/null || true

# Verify deletion
EXISTING_CODE=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM codes WHERE code = '99441'" 2>/dev/null || echo "0")
if [ "$EXISTING_CODE" != "0" ]; then
    echo "WARNING: Could not remove existing code 99441"
else
    echo "Confirmed: Code 99441 does not exist in database"
fi

# Record initial code count (for CPT4 type)
echo "Recording initial CPT4 code count..."
# Get the ct_id for CPT4
CPT4_ID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT ct_id FROM code_types WHERE ct_key = 'CPT4' LIMIT 1" 2>/dev/null || echo "1")
echo "$CPT4_ID" > /tmp/cpt4_type_id.txt
echo "CPT4 type ID: $CPT4_ID"

INITIAL_CPT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM codes WHERE code_type = $CPT4_ID" 2>/dev/null || echo "0")
echo "$INITIAL_CPT_COUNT" > /tmp/initial_cpt_count.txt
echo "Initial CPT4 code count: $INITIAL_CPT_COUNT"

# Record total codes count
INITIAL_TOTAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT COUNT(*) FROM codes" 2>/dev/null || echo "0")
echo "$INITIAL_TOTAL_COUNT" > /tmp/initial_total_codes.txt
echo "Initial total codes: $INITIAL_TOTAL_COUNT"

# Ensure Firefox is running on OpenEMR
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Add Fee Schedule Code Task Setup Complete ==="
echo ""
echo "Task: Add a new CPT procedure code to the fee schedule"
echo ""
echo "Required Details:"
echo "  - Code Type: CPT4"
echo "  - Code: 99441"  
echo "  - Description: Telephone E/M by physician, 5-10 min"
echo "  - Fee: \$45.00"
echo ""
echo "Login Credentials:"
echo "  - Username: admin"
echo "  - Password: pass"
echo ""
echo "Navigate to: Administration > Codes"
echo ""