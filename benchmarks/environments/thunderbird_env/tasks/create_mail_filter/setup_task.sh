#!/bin/bash
echo "=== Setting up create_mail_filter task ==="

source /workspace/scripts/task_utils.sh

# Record initial state of filters
MSGFILTER_FILE="${THUNDERBIRD_PROFILE}/Mail/Local Folders/msgFilterRules.dat"
INITIAL_FILTER_COUNT=0
if [ -f "$MSGFILTER_FILE" ]; then
    INITIAL_FILTER_COUNT=$(grep -c "^name=" "$MSGFILTER_FILE" 2>/dev/null || echo "0")
fi
echo "$INITIAL_FILTER_COUNT" > /tmp/initial_filter_count
echo "Initial filter count: $INITIAL_FILTER_COUNT"

# Ensure "Urgent" folder does NOT exist yet
if folder_exists "Urgent"; then
    rm -f "${LOCAL_MAIL_DIR}/Urgent" 2>/dev/null
    rm -f "${LOCAL_MAIL_DIR}/Urgent.msf" 2>/dev/null
    echo "Removed pre-existing Urgent folder"
fi

# Start Thunderbird if not running
start_thunderbird

# Wait for Thunderbird window to appear
wait_for_thunderbird_window 30

# Maximize the window
sleep 3
maximize_thunderbird

# Take initial screenshot
take_screenshot /tmp/thunderbird_task_start.png

echo "=== create_mail_filter task setup complete ==="
