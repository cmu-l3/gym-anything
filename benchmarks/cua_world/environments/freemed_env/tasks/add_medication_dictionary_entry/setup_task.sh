#!/bin/bash
echo "=== Setting up add_medication_dictionary_entry task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Determine the actual table name used for medications in this FreeMED version
MED_TABLE="medication"
if ! freemed_query "DESCRIBE medication" >/dev/null 2>&1; then
    if freemed_query "DESCRIBE medications" >/dev/null 2>&1; then 
        MED_TABLE="medications"
    elif freemed_query "DESCRIBE drugs" >/dev/null 2>&1; then 
        MED_TABLE="drugs"
    fi
fi
echo "$MED_TABLE" > /tmp/med_table_name.txt

# Ensure clean state: remove any pre-existing Wegovy/semaglutide entries
freemed_query "DELETE FROM $MED_TABLE WHERE medname LIKE '%Wegovy%' OR medgeneric LIKE '%semaglutide%'" 2>/dev/null || true

# Record initial count of medications
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM $MED_TABLE" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_med_count.txt
echo "Initial medication count in $MED_TABLE: $INITIAL_COUNT"

# Ensure Firefox is running and navigated to FreeMED
ensure_firefox_running "http://localhost/freemed/"

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task Setup Complete ==="
echo "Target: Add 'Wegovy' (semaglutide) 2.4 mg to the medication dictionary."