#!/bin/bash
set -e
echo "=== Setting up task: relocate_class_section ==="

# 1. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for MariaDB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# 3. Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e"

# 4. Prepare Data
# Get current school year and school ID (assuming ID 1)
SYEAR=$($MYSQL_CMD "SELECT syear FROM schools WHERE id=1 LIMIT 1" 2>/dev/null || echo "2025")
SCHOOL_ID=1

echo "Setting up data for SYEAR: $SYEAR"

# Clean up previous runs
$MYSQL_CMD "DELETE FROM course_periods WHERE course_id IN (SELECT course_id FROM courses WHERE course_title='Introduction to Biology');" 2>/dev/null || true
$MYSQL_CMD "DELETE FROM courses WHERE course_title='Introduction to Biology';" 2>/dev/null || true
$MYSQL_CMD "DELETE FROM rooms WHERE title IN ('Room 304', 'Science Lab');" 2>/dev/null || true

# Create Rooms
$MYSQL_CMD "INSERT INTO rooms (school_id, syear, title, capacity, sort_order) VALUES ($SCHOOL_ID, $SYEAR, 'Room 304', 30, 1);"
$MYSQL_CMD "INSERT INTO rooms (school_id, syear, title, capacity, sort_order) VALUES ($SCHOOL_ID, $SYEAR, 'Science Lab', 24, 2);"

# Get Room IDs
ROOM_304_ID=$($MYSQL_CMD "SELECT room_id FROM rooms WHERE title='Room 304' AND school_id=$SCHOOL_ID LIMIT 1")
LAB_ID=$($MYSQL_CMD "SELECT room_id FROM rooms WHERE title='Science Lab' AND school_id=$SCHOOL_ID LIMIT 1")

# Ensure Periods Exist (P2 and P3)
$MYSQL_CMD "INSERT IGNORE INTO school_periods (school_id, syear, title, short_name, sort_order, length, start_time, end_time) VALUES ($SCHOOL_ID, $SYEAR, 'Period 2', 'P2', 2, 55, '09:00:00', '09:55:00');"
$MYSQL_CMD "INSERT IGNORE INTO school_periods (school_id, syear, title, short_name, sort_order, length, start_time, end_time) VALUES ($SCHOOL_ID, $SYEAR, 'Period 3', 'P3', 3, 55, '10:00:00', '10:55:00');"

P2_ID=$($MYSQL_CMD "SELECT period_id FROM school_periods WHERE short_name='P2' AND school_id=$SCHOOL_ID LIMIT 1")
P3_ID=$($MYSQL_CMD "SELECT period_id FROM school_periods WHERE short_name='P3' AND school_id=$SCHOOL_ID LIMIT 1")

# Create Course
# Subject ID 1 is usually Math/Science in default install, or we insert if needed. 
# We'll assume subject_id 1 exists or use 0.
$MYSQL_CMD "INSERT INTO courses (school_id, subject_id, course_title, short_name, grade_level, credits) VALUES ($SCHOOL_ID, 1, 'Introduction to Biology', 'BIO101', '10', 1.0);"
COURSE_ID=$($MYSQL_CMD "SELECT course_id FROM courses WHERE course_title='Introduction to Biology' AND school_id=$SCHOOL_ID LIMIT 1")

# Create Sections (Course Periods)
# Marking period ID 1 is usually Full Year
MP_ID=$($MYSQL_CMD "SELECT marking_period_id FROM school_years WHERE school_id=$SCHOOL_ID LIMIT 1" 2>/dev/null || echo "1")

# Target Section: Period 2 in Room 304
$MYSQL_CMD "INSERT INTO course_periods (course_id, period_id, room_id, total_seats, marking_period_id, short_name) VALUES ($COURSE_ID, $P2_ID, $ROOM_304_ID, 25, $MP_ID, 'BIO101-01');"
TARGET_SECTION_ID=$($MYSQL_CMD "SELECT course_period_id FROM course_periods WHERE course_id=$COURSE_ID AND period_id=$P2_ID LIMIT 1")

# Distractor Section: Period 3 in Room 304
$MYSQL_CMD "INSERT INTO course_periods (course_id, period_id, room_id, total_seats, marking_period_id, short_name) VALUES ($COURSE_ID, $P3_ID, $ROOM_304_ID, 25, $MP_ID, 'BIO101-02');"
DISTRACTOR_SECTION_ID=$($MYSQL_CMD "SELECT course_period_id FROM course_periods WHERE course_id=$COURSE_ID AND period_id=$P3_ID LIMIT 1")

# 5. Save IDs for Verification
cat > /tmp/initial_ids.json << EOF
{
    "course_id": $COURSE_ID,
    "p2_id": $P2_ID,
    "p3_id": $P3_ID,
    "room_304_id": $ROOM_304_ID,
    "science_lab_id": $LAB_ID,
    "target_section_id": $TARGET_SECTION_ID,
    "distractor_section_id": $DISTRACTOR_SECTION_ID
}
EOF

# 6. Setup Browser
# Kill existing Chrome
pkill -f chrome 2>/dev/null || true
sleep 1

# Launch Chrome
echo "Launching Chrome..."
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
    --disable-dev-shm-usage \
    --window-size=1920,1080 \
    --password-store=basic \
    "http://localhost/opensis/" > /dev/null 2>&1 &

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
wmctrl -a "Chrome" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="