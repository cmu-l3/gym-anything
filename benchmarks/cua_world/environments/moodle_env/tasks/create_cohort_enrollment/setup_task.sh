#!/bin/bash
# Setup script for Create Cohort Enrollment task

echo "=== Setting up Create Cohort Enrollment Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type moodle_query &>/dev/null; then
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
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
    get_firefox_window_id() { DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'; }
    focus_window() { DISPLAY=:1 wmctrl -ia "$1" 2>/dev/null || true; sleep 0.3; }
    wait_for_window() {
        local window_pattern="$1"; local timeout=${2:-30}; local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then return 0; fi
            sleep 1; elapsed=$((elapsed + 1))
        done
        return 1
    }
fi

# 1. Ensure CHEM101 exists
echo "Checking for CHEM101 course..."
COURSE_CHECK=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')

if [ -z "$COURSE_CHECK" ]; then
    echo "Creating CHEM101 course..."
    # Get Science category ID or default to 1
    CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science' LIMIT 1" | tr -d '[:space:]')
    CAT_ID=${CAT_ID:-1}
    
    # Create course via PHP CLI to ensure proper initialization
    sudo -u www-data php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/moodle/config.php');
        \$course = new stdClass();
        \$course->fullname = 'General Chemistry';
        \$course->shortname = 'CHEM101';
        \$course->category = $CAT_ID;
        \$course->startdate = time();
        \$course->visible = 1;
        try {
            \$created_course = create_course(\$course);
            echo 'Created course ID: ' . \$created_course->id;
        } catch (Exception \$e) {
            echo 'Error: ' . \$e->getMessage();
            exit(1);
        }
    "
    COURSE_CHECK=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')
fi
echo "Target Course ID: $COURSE_CHECK"

# 2. CLEANUP: Delete the cohort if it already exists (from previous runs)
echo "Cleaning up any existing target cohorts..."
COHORT_ID=$(moodle_query "SELECT id FROM mdl_cohort WHERE idnumber='BIOMAJ-F25'" | tr -d '[:space:]')
if [ -n "$COHORT_ID" ]; then
    echo "Removing existing cohort $COHORT_ID..."
    moodle_query "DELETE FROM mdl_cohort WHERE id=$COHORT_ID"
    moodle_query "DELETE FROM mdl_cohort_members WHERE cohortid=$COHORT_ID"
    # Remove any enrol instances linked to this cohort
    moodle_query "DELETE FROM mdl_enrol WHERE enrol='cohort' AND customint1=$COHORT_ID"
fi

# 3. Ensure target users exist
echo "Verifying users..."
MISSING_USERS=0
for USER in jsmith mjones awilson bbrown; do
    UID=$(moodle_query "SELECT id FROM mdl_user WHERE username='$USER' AND deleted=0" | tr -d '[:space:]')
    if [ -z "$UID" ]; then
        echo "WARNING: User $USER not found!"
        MISSING_USERS=$((MISSING_USERS + 1))
    fi
done

if [ "$MISSING_USERS" -gt 0 ]; then
    echo "ERROR: Required users are missing. Re-run setup_moodle.sh or check installation."
    exit 1
fi

# Record start time for timestamp verification
date +%s > /tmp/task_start_timestamp

# 4. Start Firefox
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|Moodle" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="