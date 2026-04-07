#!/bin/bash
set -e

echo "=== Setting up Configure Course Prerequisite task ==="

# 1. Source utilities/Env setup
export DISPLAY=${DISPLAY:-:1}
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 2. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure Services are running
echo "Checking database..."
service mariadb start 2>/dev/null || systemctl start mariadb
sleep 2

# 4. Data Preparation: Ensure Courses Exist and Clean State
# We need 'Biology I' (BIO101) and 'Anatomy & Physiology' (BIO201)
# We also need to REMOVE any existing prerequisite link between them to ensure the agent actually does the work.

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e"

echo "Preparing database records..."

# Insert Biology I if not exists
$MYSQL_CMD "INSERT INTO courses (course_title, course_code, subject_id, grade_level, credits, sort_order) 
SELECT 'Biology I', 'BIO101', 1, '09', 1.0, 10 
WHERE NOT EXISTS (SELECT 1 FROM courses WHERE course_code='BIO101');" 2>/dev/null || \
$MYSQL_CMD "INSERT INTO courses (course_name, course_code, subject_area, grade_level, credits) 
VALUES ('Biology I', 'BIO101', 'Science', '09', 1.0);" 2>/dev/null || true

# Insert Anatomy & Physiology if not exists
$MYSQL_CMD "INSERT INTO courses (course_title, course_code, subject_id, grade_level, credits, sort_order) 
SELECT 'Anatomy & Physiology', 'BIO201', 1, '11', 1.0, 20 
WHERE NOT EXISTS (SELECT 1 FROM courses WHERE course_code='BIO201');" 2>/dev/null || \
$MYSQL_CMD "INSERT INTO courses (course_name, course_code, subject_area, grade_level, credits) 
VALUES ('Anatomy & Physiology', 'BIO201', 'Science', '11', 1.0);" 2>/dev/null || true

# Get IDs for verification and cleaning
ID_BIO=$($MYSQL_CMD "SELECT course_id FROM courses WHERE course_code='BIO101' LIMIT 1")
ID_ANATOMY=$($MYSQL_CMD "SELECT course_id FROM courses WHERE course_code='BIO201' LIMIT 1")

echo "Course IDs: BIO101=$ID_BIO, BIO201=$ID_ANATOMY"

# CRITICAL: Clean existing prerequisites for the target course
if [ -n "$ID_ANATOMY" ]; then
    echo "Clearing existing prerequisites for Anatomy & Physiology..."
    $MYSQL_CMD "DELETE FROM course_reqs WHERE course_id='$ID_ANATOMY';" 2>/dev/null || true
fi

# Record initial count (should be 0)
INITIAL_COUNT=$($MYSQL_CMD "SELECT COUNT(*) FROM course_reqs WHERE course_id='$ID_ANATOMY'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_prereq_count.txt

# 5. Application Setup (Browser)
echo "Setting up Browser..."

# Kill existing Chrome
pkill -f chrome 2>/dev/null || true
sleep 1

# Start Chrome pointing to OpenSIS
if command -v google-chrome-stable &> /dev/null; then
    CHROME="google-chrome-stable"
else
    CHROME="chromium-browser"
fi

su - ga -c "DISPLAY=:1 $CHROME --no-first-run --no-default-browser-check --start-maximized --password-store=basic 'http://localhost/opensis/' &"

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Maximize and focus
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Chrome" 2>/dev/null || true

# 6. Initial Screenshot
scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="