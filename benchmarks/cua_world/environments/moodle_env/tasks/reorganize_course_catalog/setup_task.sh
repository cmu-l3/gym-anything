#!/bin/bash
# Setup script for Reorganize Course Catalog task

echo "=== Setting up Reorganize Course Catalog Task ==="

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
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
fi

# 1. Ensure "Science" category exists (default home for BIO101)
echo "Checking for 'Science' category..."
SCIENCE_CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science' LIMIT 1" | tr -d '[:space:]')

if [ -z "$SCIENCE_CAT_ID" ]; then
    echo "Creating Science category..."
    # Quick insert if missing (unlikely given env setup)
    moodle_query "INSERT INTO mdl_course_categories (name, idnumber, description, parent, sortorder, visible, visibleold, timemodified, depth, path, theme) VALUES ('Science', 'SCI', 'Science Department', 0, 10000, 1, 1, UNIX_TIMESTAMP(), 1, '/1', '')"
    SCIENCE_CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science' LIMIT 1" | tr -d '[:space:]')
fi
echo "Science Category ID: $SCIENCE_CAT_ID"

# 2. Reset State: Move BIO101 back to Science if it's elsewhere
echo "Ensuring BIO101 is in Science..."
BIO101_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

if [ -n "$BIO101_ID" ]; then
    moodle_query "UPDATE mdl_course SET category=$SCIENCE_CAT_ID WHERE id=$BIO101_ID"
else
    echo "ERROR: BIO101 course not found!"
    exit 1
fi

# 3. Clean up: Delete "Life Sciences" and "Archived Life Sciences" if they exist from previous runs
echo "Cleaning up previous task artifacts..."
moodle_query "DELETE FROM mdl_course_categories WHERE idnumber='LIFESCI' OR idnumber='LIFESCI_ARCHIVE'"
moodle_query "DELETE FROM mdl_course_categories WHERE name='Life Sciences' OR name='Archived Life Sciences'"

# Record task start time
date +%s > /tmp/task_start_timestamp

# Record initial category count for validation
INITIAL_CAT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_categories" | tr -d '[:space:]')
echo "$INITIAL_CAT_COUNT" > /tmp/initial_cat_count

# Ensure Firefox is running
echo "Starting Firefox..."
MOODLE_URL="http://localhost/moodle/admin/search.php" # Go to admin search to hint at admin tasks
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|Moodle" 30

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="