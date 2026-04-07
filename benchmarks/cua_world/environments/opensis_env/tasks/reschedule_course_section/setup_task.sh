#!/bin/bash
set -e
echo "=== Setting up Reschedule Course Section task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true
sleep 3

MYSQL_CMD="mysql"
if ! mysql -u root -e "SELECT 1" &>/dev/null; then
    MYSQL_CMD="sudo mysql"
fi

DB_NAME="opensis"
# Use root to setup, app uses opensis_user
DB_USER="root" 

# Calculate current school year logic matching OpenSIS logic
CURRENT_YEAR=$(date +%Y)
CURRENT_MONTH=$(date +%m)
if [ "$CURRENT_MONTH" -ge 8 ]; then
    SYEAR=$((CURRENT_YEAR + 1))
else
    SYEAR=$CURRENT_YEAR
fi

# 1. Ensure Periods 1-5 exist
echo "Setting up school periods..."
$MYSQL_CMD $DB_NAME <<PERIODS_SQL
INSERT INTO school_periods (period_id, syear, school_id, sort_order, title, short_name, length, attendance)
VALUES
(1, $SYEAR, 1, 1, 'Period 1', '1', 50, 'Y'),
(2, $SYEAR, 1, 2, 'Period 2', '2', 50, 'Y'),
(3, $SYEAR, 1, 3, 'Period 3', '3', 50, 'Y'),
(4, $SYEAR, 1, 4, 'Period 4', '4', 50, 'Y'),
(5, $SYEAR, 1, 5, 'Period 5', '5', 50, 'Y')
ON DUPLICATE KEY UPDATE title=VALUES(title);
PERIODS_SQL

# 2. Ensure Course exists
echo "Setting up course ENG101..."
# Delete if exists to ensure clean slate or update? Update is safer to keep IDs
$MYSQL_CMD $DB_NAME <<COURSE_SQL
INSERT INTO courses (syear, school_id, title, short_name, subject_id, grade_level, credits)
VALUES ($SYEAR, 1, 'Introduction to Literature', 'ENG101', 0, NULL, 1.0)
ON DUPLICATE KEY UPDATE title='Introduction to Literature';
COURSE_SQL

# Get Course ID
COURSE_ID=$($MYSQL_CMD $DB_NAME -N -e "SELECT course_id FROM courses WHERE short_name='ENG101' AND syear=$SYEAR LIMIT 1")
echo "Course ID: $COURSE_ID"

# 3. Create Course Section (Period 1, Room 101)
# We delete existing sections for this course to ensure clean state
echo "Setting up course section..."
$MYSQL_CMD $DB_NAME -e "DELETE FROM course_periods WHERE course_id=$COURSE_ID AND syear=$SYEAR"

# Insert new section
$MYSQL_CMD $DB_NAME <<SECTION_SQL
INSERT INTO course_periods (syear, school_id, course_id, period_id, room, marking_period_id, filled_seats, total_seats, title, short_name)
VALUES ($SYEAR, 1, $COURSE_ID, 1, '101', 1, 0, 30, 'Introduction to Literature - 1', 'ENG101-1');
SECTION_SQL

# 4. Ensure Admin has scheduling permissions
echo "Configuring permissions..."
$MYSQL_CMD $DB_NAME <<PERMS_SQL
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit) VALUES
(1, 'scheduling/Courses.php', 'Y', 'Y'),
(1, 'scheduling/Schdule.php', 'Y', 'Y')
ON DUPLICATE KEY UPDATE can_use='Y', can_edit='Y';
PERMS_SQL

# 5. Record Initial State for Anti-Gaming
echo "Recording initial state..."
INITIAL_SECTION=$($MYSQL_CMD $DB_NAME -N -e "SELECT period_id, room FROM course_periods WHERE course_id=$COURSE_ID AND syear=$SYEAR LIMIT 1")
echo "$INITIAL_SECTION" > /tmp/initial_section_state.txt
echo "SYEAR=$SYEAR" > /tmp/syear.txt

# 6. Launch Chrome
echo "Launching Chrome..."
pkill -f chrome 2>/dev/null || true
sleep 1

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --window-size=1920,1080 \
    --password-store=basic \
    "http://localhost/opensis/" > /home/ga/chrome.log 2>&1 &

sleep 5

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

wmctrl -a "Chrome" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="