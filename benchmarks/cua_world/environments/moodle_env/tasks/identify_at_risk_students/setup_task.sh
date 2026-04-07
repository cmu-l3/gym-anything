#!/bin/bash
# Setup script for Identify At-Risk Students task

echo "=== Setting up Identify At-Risk Students Task ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if not sourced
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
fi

# 1. Create Course CHEM101 if not exists
echo "Creating/Checking CHEM101 course..."
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')

if [ -z "$COURSE_ID" ]; then
    # Create category first if needed (id=1 is default)
    # Insert course
    cat_id=1
    time_now=$(date +%s)
    # Manual insert usually risky, but using PHP CLI is verbose. We'll use simple SQL for speed in setup
    # Note: Using Moodle CLI or API is better, but raw SQL works for simple setup if cache cleared
    # Let's try to use the PHP script method from install_moodle.sh for robustness if possible, 
    # but for this specific task, we'll assume the environment allows PHP execution.
    
    sudo -u www-data php -r "
        define('CLI_SCRIPT', true);
        require('/var/www/html/moodle/config.php');
        \$course = new stdClass();
        \$course->fullname = 'Chemistry 101';
        \$course->shortname = 'CHEM101';
        \$course->category = 1;
        \$course->startdate = time() - (60*60*24*60); // Started 60 days ago
        \$course->visible = 1;
        try {
            \$c = create_course(\$course);
            echo \$c->id;
        } catch (Exception \$e) { echo ''; }
    " > /tmp/new_course_id
    COURSE_ID=$(cat /tmp/new_course_id)
fi

echo "CHEM101 Course ID: $COURSE_ID"

# 2. Ensure Users Exist
# We need 5 specific users: dlee, epatel (inactive), fkim, awilson, bbrown (active)
USERS=("dlee" "epatel" "fkim" "awilson" "bbrown")

echo "Ensuring users exist..."
sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    require_once(\$CFG->dirroot . '/user/lib.php');
    
    \$users_to_check = ['dlee', 'epatel', 'fkim', 'awilson', 'bbrown'];
    foreach (\$users_to_check as \$uname) {
        if (!\core_user::get_user_by_username(\$uname)) {
            \$user = new stdClass();
            \$user->username = \$uname;
            \$user->firstname = ucfirst(\$uname);
            \$user->lastname = 'Student';
            \$user->email = \$uname . '@example.com';
            \$user->password = 'Student1234!';
            \$user->confirmed = 1;
            \$user->mnethostid = \$CFG->mnet_localhost_id;
            user_create_user(\$user);
            echo 'Created ' . \$uname . '\n';
        }
    }
"

# 3. Enroll Users in CHEM101
echo "Enrolling users..."
sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    require_once(\$CFG->dirroot . '/enrol/manual/locallib.php');
    
    \$course = \$DB->get_record('course', ['shortname' => 'CHEM101']);
    \$enrol = \$DB->get_record('enrol', ['courseid' => \$course->id, 'enrol' => 'manual']);
    \$plugin = enrol_get_plugin('manual');
    
    \$users = ['dlee', 'epatel', 'fkim', 'awilson', 'bbrown'];
    \$roleid = \$DB->get_record('role', ['shortname' => 'student'])->id;
    
    foreach (\$users as \$uname) {
        \$u = \core_user::get_user_by_username(\$uname);
        if (!is_enrolled(context_course::instance(\$course->id), \$u->id)) {
            \$plugin->enrol_user(\$enrol, \$u->id, \$roleid);
            echo 'Enrolled ' . \$uname . '\n';
        }
    }
"

# 4. Manipulate Timestamps for Verification (CRITICAL)
# dlee, epatel -> Inactive (Last access > 30 days ago)
# fkim, awilson, bbrown -> Active (Last access < 5 days ago)

NOW=$(date +%s)
DAY_SEC=86400
INACTIVE_TIME=$((NOW - (45 * DAY_SEC))) # 45 days ago
ACTIVE_TIME=$((NOW - (2 * DAY_SEC)))    # 2 days ago

echo "Manipulating access timestamps..."

# Update dlee (inactive)
moodle_query "UPDATE mdl_user SET lastaccess=$INACTIVE_TIME, currentlogin=$INACTIVE_TIME WHERE username='dlee'"
moodle_query "UPDATE mdl_user_enrolments SET timecreated=$((INACTIVE_TIME - 1000)) WHERE userid=(SELECT id FROM mdl_user WHERE username='dlee')"
# Insert/Update mdl_user_lastaccess (course specific access)
# Check if record exists first to decide insert vs update is tedious in bash, so we use REPLACE INTO if unique key exists or generic update
USER_ID_DLEE=$(moodle_query "SELECT id FROM mdl_user WHERE username='dlee'" | tr -d '[:space:]')
moodle_query "DELETE FROM mdl_user_lastaccess WHERE userid=$USER_ID_DLEE AND courseid=$COURSE_ID"
moodle_query "INSERT INTO mdl_user_lastaccess (userid, courseid, timeaccess) VALUES ($USER_ID_DLEE, $COURSE_ID, $INACTIVE_TIME)"

# Update epatel (inactive)
moodle_query "UPDATE mdl_user SET lastaccess=$INACTIVE_TIME, currentlogin=$INACTIVE_TIME WHERE username='epatel'"
USER_ID_EPATEL=$(moodle_query "SELECT id FROM mdl_user WHERE username='epatel'" | tr -d '[:space:]')
moodle_query "DELETE FROM mdl_user_lastaccess WHERE userid=$USER_ID_EPATEL AND courseid=$COURSE_ID"
moodle_query "INSERT INTO mdl_user_lastaccess (userid, courseid, timeaccess) VALUES ($USER_ID_EPATEL, $COURSE_ID, $INACTIVE_TIME)"

# Update active users
for USERNAME in fkim awilson bbrown; do
    moodle_query "UPDATE mdl_user SET lastaccess=$ACTIVE_TIME, currentlogin=$ACTIVE_TIME WHERE username='$USERNAME'"
    UID=$(moodle_query "SELECT id FROM mdl_user WHERE username='$USERNAME'" | tr -d '[:space:]')
    moodle_query "DELETE FROM mdl_user_lastaccess WHERE userid=$UID AND courseid=$COURSE_ID"
    moodle_query "INSERT INTO mdl_user_lastaccess (userid, courseid, timeaccess) VALUES ($UID, $COURSE_ID, $ACTIVE_TIME)"
done

# Clear Moodle cache to ensure timestamp changes are reflected in UI
sudo -u www-data php /var/www/html/moodle/admin/cli/purge_caches.php > /dev/null 2>&1

# Record Task Start Time
date +%s > /tmp/task_start_time.txt

# Start Firefox
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/moodle/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Setup Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Users dlee and epatel set to INACTIVE (45 days)."
echo "Users fkim, awilson, bbrown set to ACTIVE (2 days)."