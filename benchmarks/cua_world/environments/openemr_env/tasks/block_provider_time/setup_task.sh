#!/bin/bash
# Setup script for Block Provider Time task

echo "=== Setting up Block Provider Time Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Provider details
PROVIDER_ID=1
PROVIDER_USERNAME="admin"

# Calculate target date (3 business days from today)
calculate_business_days() {
    local days_to_add=$1
    local current_date=$(date +%Y-%m-%d)
    local business_days=0
    local check_date="$current_date"
    
    while [ $business_days -lt $days_to_add ]; do
        # Add one day
        check_date=$(date -d "$check_date + 1 day" +%Y-%m-%d)
        # Get day of week (1=Monday, 7=Sunday)
        local dow=$(date -d "$check_date" +%u)
        # Only count weekdays (Monday-Friday = 1-5)
        if [ $dow -le 5 ]; then
            business_days=$((business_days + 1))
        fi
    done
    
    echo "$check_date"
}

TARGET_DATE=$(calculate_business_days 3)
echo "Target date (3 business days from today): $TARGET_DATE"
echo "$TARGET_DATE" > /tmp/target_date.txt

# Record task start timestamp
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp.txt
echo "Task start timestamp: $TASK_START"

# Record initial calendar event count for this provider
echo "Recording initial calendar event count..."
INITIAL_EVENT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_aid=$PROVIDER_ID" 2>/dev/null || echo "0")
echo "$INITIAL_EVENT_COUNT" > /tmp/initial_event_count.txt
echo "Initial event count for provider $PROVIDER_ID: $INITIAL_EVENT_COUNT"

# Also record events on the target date specifically
INITIAL_TARGET_DATE_EVENTS=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_aid=$PROVIDER_ID AND pc_eventDate='$TARGET_DATE'" 2>/dev/null || echo "0")
echo "$INITIAL_TARGET_DATE_EVENTS" > /tmp/initial_target_date_events.txt
echo "Initial events on target date ($TARGET_DATE): $INITIAL_TARGET_DATE_EVENTS"

# Verify provider exists
echo "Verifying provider exists..."
PROVIDER_CHECK=$(openemr_query "SELECT id, username, fname, lname FROM users WHERE id=$PROVIDER_ID" 2>/dev/null)
if [ -z "$PROVIDER_CHECK" ]; then
    echo "WARNING: Provider not found in database!"
else
    echo "Provider found: $PROVIDER_CHECK"
fi

# Ensure Firefox is running on OpenEMR login page
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
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Block Provider Time Task Setup Complete ==="
echo ""
echo "Task: Block provider's calendar for Compliance Training"
echo ""
echo "Details:"
echo "  Provider: Administrator, Administrator (admin)"
echo "  Target Date: $TARGET_DATE (3 business days from today)"
echo "  Time: 2:00 PM - 3:30 PM (14:00 - 15:30)"
echo "  Duration: 90 minutes"
echo "  Description: 'Compliance Training'"
echo ""
echo "Instructions:"
echo "  1. Log in to OpenEMR (admin / pass)"
echo "  2. Navigate to Calendar"
echo "  3. Navigate to date: $TARGET_DATE"
echo "  4. Create a blocked time/event (NOT a patient appointment)"
echo "  5. Save the entry"
echo ""