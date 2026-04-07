#!/bin/bash
echo "=== Setting up add_billing_modifier task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Identify the modifier table dynamically (usually 'modifier' in FreeMED)
MODIFIER_TABLE=$(freemed_query "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='freemed' AND TABLE_NAME LIKE '%modifier%' LIMIT 1" 2>/dev/null)
MODIFIER_TABLE=${MODIFIER_TABLE:-modifier}
echo "$MODIFIER_TABLE" > /tmp/modifier_table_name.txt

# Clean up any pre-existing '95' modifiers to ensure a pristine state
# We try a few common column names (ignoring errors if columns don't exist)
freemed_query "DELETE FROM $MODIFIER_TABLE WHERE modifier='95' OR mod_code='95' OR id='95'" 2>/dev/null || true

# Record initial count and max ID to detect new insertions
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM $MODIFIER_TABLE" 2>/dev/null || echo "0")
MAX_ID=$(freemed_query "SELECT MAX(id) FROM $MODIFIER_TABLE" 2>/dev/null || echo "0")
if [ -z "$MAX_ID" ] || [ "$MAX_ID" == "NULL" ]; then MAX_ID=0; fi

echo "$INITIAL_COUNT" > /tmp/initial_modifier_count.txt
echo "$MAX_ID" > /tmp/initial_modifier_max_id.txt

echo "Initial table: $MODIFIER_TABLE"
echo "Initial count: $INITIAL_COUNT"
echo "Initial max ID: $MAX_ID"

# Ensure Firefox is running and at the login screen
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_modifier_start.png

echo "=== Setup complete ==="