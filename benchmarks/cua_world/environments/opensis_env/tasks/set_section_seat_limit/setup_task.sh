#!/bin/bash
set -e
echo "=== Setting up set_section_seat_limit task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Start Services
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true
sleep 3

# 2. Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# 3. Get Context (School ID, Year)
SYEAR=$($MYSQL_CMD -N -e "SELECT syear FROM schools WHERE id=1 LIMIT 1" 2>/dev/null || echo "2025")
echo "Using SYEAR=$SYEAR"

# 4. Clean previous data (idempotency)
echo "Cleaning old data..."
$MYSQL_CMD -e "DELETE FROM course_periods WHERE course_id IN (SELECT course_id FROM courses WHERE course_code IN ('ART-205', 'ART-101'));" 2>/dev/null || true
$MYSQL_CMD -e "DELETE FROM courses WHERE course_code IN ('ART-205', 'ART-101');" 2>/dev/null || true

# 5. Insert Data: Subject Area (if needed)
SUBJECT_ID=$($MYSQL_CMD -N -e "SELECT id FROM course_subjects LIMIT 1" 2>/dev/null)
if [ -z "$SUBJECT_ID" ]; then
    $MYSQL_CMD -e "INSERT INTO course_subjects (title, short_name, school_id) VALUES ('Arts', 'ART', 1);"
    SUBJECT_ID=$($MYSQL_CMD -N -e "SELECT LAST_INSERT_ID();")
fi

# 6. Insert Data: Courses
echo "Inserting courses..."
# ART-205: Introduction to Ceramics
$MYSQL_CMD -e "INSERT INTO courses (syear, school_id, subject_id, course_name, course_code, grade_level) VALUES ($SYEAR, 1, $SUBJECT_ID, 'Introduction to Ceramics', 'ART-205', 0);"
COURSE_ID_CERAMICS=$($MYSQL_CMD -N -e "SELECT course_id FROM courses WHERE course_code='ART-205' LIMIT 1;")

# ART-101: Drawing 101 (Control Group)
$MYSQL_CMD -e "INSERT INTO courses (syear, school_id, subject_id, course_name, course_code, grade_level) VALUES ($SYEAR, 1, $SUBJECT_ID, 'Drawing 101', 'ART-101', 0);"
COURSE_ID_DRAWING=$($MYSQL_CMD -N -e "SELECT course_id FROM courses WHERE course_code='ART-101' LIMIT 1;")

# 7. Insert Data: Sections (Course Periods)
MP_ID=$($MYSQL_CMD -N -e "SELECT marking_period_id FROM school_years WHERE school_id=1 AND syear=$SYEAR LIMIT 1;" || echo "1")

# Use 'total_seats' column (standard OpenSIS)
# Insert Section 01 for Ceramics (Seats=25)
$MYSQL_CMD -e "INSERT INTO course_periods (course_id, short_name, title, marking_period_id, total_seats, mp) VALUES ($COURSE_ID_CERAMICS, '01', 'Section 01', $MP_ID, 25, 'FY');"

# Insert Section 01 for Drawing (Seats=25) - Control
$MYSQL_CMD -e "INSERT INTO course_periods (course_id, short_name, title, marking_period_id, total_seats, mp) VALUES ($COURSE_ID_DRAWING, '01', 'Section 01', $MP_ID, 25, 'FY');"

echo "Data inserted: Ceramics (ID: $COURSE_ID_CERAMICS) and Drawing (ID: $COURSE_ID_DRAWING) with 25 seats."

# 8. Browser Setup
# Kill existing
pkill -f "chrome" || true
pkill -f "chromium" || true

# Launch Chrome
echo "Launching browser..."
if command -v google-chrome-stable &> /dev/null; then
    BROWSER="google-chrome-stable"
else
    BROWSER="chromium-browser"
fi

su - ga -c "DISPLAY=:1 $BROWSER --start-maximized --no-sandbox http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome\|Chromium"; then
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || DISPLAY=:1 wmctrl -a "Chromium" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="