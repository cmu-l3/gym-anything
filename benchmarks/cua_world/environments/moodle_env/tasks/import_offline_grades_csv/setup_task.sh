#!/bin/bash
# Setup script for Import Offline Grades CSV task

echo "=== Setting up Import Offline Grades Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
fi

# 1. Create the CSV file
echo "Creating CSV file..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/lab_scores.csv << EOF
Student Email,Practical Result
jsmith@example.com,85
mjones@example.com,92
awilson@example.com,78
EOF
chown ga:ga /home/ga/Documents/lab_scores.csv

# 2. Get Course ID for BIO101
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found!"
    exit 1
fi
echo "BIO101 Course ID: $COURSE_ID"

# 3. Create the manual grade item 'Lab Practical 1' if it doesn't exist
GRADE_ITEM_CHECK=$(moodle_query "SELECT id FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemname='Lab Practical 1' AND itemtype='manual'" | tr -d '[:space:]')

if [ -z "$GRADE_ITEM_CHECK" ]; then
    echo "Creating 'Lab Practical 1' grade item..."
    # Insert manual grade item
    # itemtype=manual, gradetype=1 (value), grademax=100, grademin=0, timecreated=now
    NOW=$(date +%s)
    moodle_query "INSERT INTO mdl_grade_items (courseid, categoryid, itemname, itemtype, gradetype, grademax, grademin, timecreated, timemodified, hidden) 
                  VALUES ($COURSE_ID, NULL, 'Lab Practical 1', 'manual', 1, 100.00, 0.00, $NOW, $NOW, 0)"
    
    # Get the ID of the new item
    GRADE_ITEM_ID=$(moodle_query "SELECT id FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemname='Lab Practical 1' AND itemtype='manual'" | tr -d '[:space:]')
    echo "Created Grade Item ID: $GRADE_ITEM_ID"
else
    GRADE_ITEM_ID="$GRADE_ITEM_CHECK"
    echo "Using existing Grade Item ID: $GRADE_ITEM_ID"
    # Ensure it's empty/clean for the task (reset grades for these users)
    # Get user IDs
    USER_IDS=$(moodle_query "SELECT id FROM mdl_user WHERE email IN ('jsmith@example.com', 'mjones@example.com', 'awilson@example.com')" | tr '\n' ',' | sed 's/,$//')
    if [ -n "$USER_IDS" ]; then
        moodle_query "DELETE FROM mdl_grade_grades WHERE itemid=$GRADE_ITEM_ID AND userid IN ($USER_IDS)"
    fi
fi

# Save the target grade item ID for export verification
echo "$GRADE_ITEM_ID" > /tmp/target_grade_item_id

# 4. Launch Firefox
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 5. Wait for window and focus
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Firefox\|Moodle"; then
        break
    fi
    sleep 1
done

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Record start time
date +%s > /tmp/task_start_time

# 7. Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Course: BIO101 ($COURSE_ID)"
echo "Target Grade Item: Lab Practical 1 ($GRADE_ITEM_ID)"
echo "CSV File: /home/ga/Documents/lab_scores.csv"