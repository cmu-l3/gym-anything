#!/bin/bash
# Setup script for Create Competency Framework task

echo "=== Setting up Competency Framework Task ==="

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
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
fi

# 1. Enable Competencies in Moodle Config
echo "Enabling competencies..."
sudo -u www-data php /var/www/html/moodle/admin/cli/cfg.php --name=enablecompetencies --set=1 > /dev/null

# 2. Create the target course CS101 if it doesn't exist
echo "Checking for CS101..."
COURSE_CHECK=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CS101'")
if [ -z "$COURSE_CHECK" ]; then
    echo "Creating CS101 course..."
    # Get a category ID (Science or default)
    CAT_ID=$(moodle_query "SELECT id FROM mdl_course_categories WHERE name='Science' LIMIT 1")
    if [ -z "$CAT_ID" ]; then CAT_ID=1; fi
    
    # Create course via PHP CLI to ensure proper initialization
    sudo -u www-data php -r "
    define('CLI_SCRIPT', true);
    require('/var/www/html/moodle/config.php');
    \$course = new stdClass();
    \$course->fullname = 'Introduction to Computer Science';
    \$course->shortname = 'CS101';
    \$course->category = $CAT_ID;
    \$course->visible = 1;
    \$course->startdate = time();
    try {
        \$created_course = create_course(\$course);
        echo 'Created course ID: ' . \$created_course->id;
    } catch (Exception \$e) {
        echo 'Error creating course: ' . \$e->getMessage();
    }
    "
fi

# 3. Create a Custom Scale "Digital Literacy Scale"
# This ensures the agent has the specific scale mentioned in description
echo "Ensuring Digital Literacy Scale exists..."
SCALE_CHECK=$(moodle_query "SELECT id FROM mdl_scale WHERE name='Digital Literacy Scale'")
if [ -z "$SCALE_CHECK" ]; then
    # Insert scale: Not yet competent,Competent,Proficient
    moodle_query "INSERT INTO mdl_scale (courseid, userid, name, scale, description, descriptionformat, timemodified) VALUES (0, 0, 'Digital Literacy Scale', 'Not yet competent,Competent,Proficient', 'Scale for digital literacy competencies', 1, UNIX_TIMESTAMP())"
fi

# 4. Record Baseline State
echo "Recording baseline counts..."
INITIAL_FW_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency_framework")
INITIAL_COMP_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency")
INITIAL_LINK_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_competency_coursecomp")

echo "$INITIAL_FW_COUNT" > /tmp/initial_fw_count
echo "$INITIAL_COMP_COUNT" > /tmp/initial_comp_count
echo "$INITIAL_LINK_COUNT" > /tmp/initial_link_count

# Record Task Start Time
date +%s > /tmp/task_start_timestamp

# 5. Launch Firefox
echo "Starting Firefox..."
MOODLE_URL="http://localhost/"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# 6. Window Management
if DISPLAY=:1 wmctrl -l | grep -q "Moodle"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep "Moodle" | awk '{print $1}' | head -1)
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="