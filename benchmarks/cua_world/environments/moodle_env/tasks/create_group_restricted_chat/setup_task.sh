#!/bin/bash
# Setup script for Create Group Restricted Chat task

echo "=== Setting up Create Group Restricted Chat Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if utils not found (safety)
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
    wait_for_window() {
        local window_pattern="$1"
        local timeout=${2:-30}
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then return 0; fi
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
fi

# 1. Get BIO101 Course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: BIO101 course not found!"
    exit 1
fi
echo "BIO101 Course ID: $COURSE_ID"

# 2. Ensure 'Project Team Alpha' group exists
GROUP_NAME="Project Team Alpha"
GROUP_ID=$(moodle_query "SELECT id FROM mdl_groups WHERE courseid=$COURSE_ID AND name='$GROUP_NAME'" | tr -d '[:space:]')

if [ -z "$GROUP_ID" ]; then
    echo "Creating group '$GROUP_NAME'..."
    # Create group via SQL directly for setup speed
    # Note: In production Moodle, using PHP API is better, but SQL is sufficient for basic setup
    moodle_query "INSERT INTO mdl_groups (courseid, name, description, descriptionformat, timecreated, timemodified) VALUES ($COURSE_ID, '$GROUP_NAME', '', 1, UNIX_TIMESTAMP(), UNIX_TIMESTAMP())"
    GROUP_ID=$(moodle_query "SELECT id FROM mdl_groups WHERE courseid=$COURSE_ID AND name='$GROUP_NAME'" | tr -d '[:space:]')
    echo "Created Group ID: $GROUP_ID"
else
    echo "Group '$GROUP_NAME' already exists (ID: $GROUP_ID)"
fi

# 3. Clean up any previous attempts (delete chat with same name)
echo "Cleaning up previous attempts..."
CHAT_ID=$(moodle_query "SELECT id FROM mdl_chat WHERE course=$COURSE_ID AND name='Alpha Team Coordination'" | tr -d '[:space:]')
if [ -n "$CHAT_ID" ]; then
    # Get course module id
    CM_ID=$(moodle_query "SELECT id FROM mdl_course_modules WHERE instance=$CHAT_ID AND module=(SELECT id FROM mdl_modules WHERE name='chat')" | tr -d '[:space:]')
    
    # Delete from database (Quick cleanup, normally should use Moodle API)
    moodle_query "DELETE FROM mdl_chat WHERE id=$CHAT_ID"
    if [ -n "$CM_ID" ]; then
        moodle_query "DELETE FROM mdl_course_modules WHERE id=$CM_ID"
        moodle_query "DELETE FROM mdl_context WHERE contextlevel=70 AND instanceid=$CM_ID"
    fi
    echo "Removed previous chat activity."
fi

# 4. Record task start timestamp
date +%s > /tmp/task_start_timestamp

# 5. Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/course/view.php?id=$COURSE_ID' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 6. Wait for window and focus
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="