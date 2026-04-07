#!/bin/bash
set -e
echo "=== Setting up Re-Enrollment Task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Database connection details
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B"

# 3. Wait for database
echo "Waiting for database..."
for i in {1..30}; do
    if mysqladmin ping -u $DB_USER -p$DB_PASS --silent; then
        break
    fi
    sleep 1
done

# 4. Prepare Data: Emily Blunt (Inactive/Withdrawn)
echo "Preparing student data..."

# Get School ID and Current School Year
SCHOOL_ID=$($MYSQL_CMD -e "SELECT id FROM schools LIMIT 1;" || echo "1")
SYEAR=$($MYSQL_CMD -e "SELECT syear FROM schools WHERE id='$SCHOOL_ID' LIMIT 1;" || echo "2025")

# Clean up any existing records for Emily Blunt to ensure fresh state
$MYSQL_CMD -e "DELETE FROM student_enrollment WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Emily' AND last_name='Blunt');" 2>/dev/null || true
$MYSQL_CMD -e "DELETE FROM students WHERE first_name='Emily' AND last_name='Blunt';" 2>/dev/null || true

# Insert Student Record
$MYSQL_CMD -e "INSERT INTO students (first_name, last_name, date_of_birth, gender, ethnicity_id, common_name, social_security, language_id) VALUES ('Emily', 'Blunt', '2007-03-15', 'Female', 1, '', '', 1);"

# Get the new Student ID
STUDENT_ID=$($MYSQL_CMD -e "SELECT student_id FROM students WHERE first_name='Emily' AND last_name='Blunt' LIMIT 1;")

# Ensure Enrollment Codes exist
# Check for 'New Enrollment' (id 1 usually) and 'Transferred' (id 2 usually) and 'Re-Enrollment'
# We will insert them if missing to be safe
$MYSQL_CMD -e "INSERT IGNORE INTO enrollment_codes (id, syear, title, short_name, type) VALUES (1, $SYEAR, 'New Enrollment', 'NEW', 'Add'), (2, $SYEAR, 'Transferred', 'TRANS', 'Drop'), (3, $SYEAR, 'Re-Enrollment', 'RETURN', 'Add');"

# Insert PAST Enrollment History (The "Withdrawn" state)
# Start date: 3 months ago, End date: 1 month ago
START_DATE=$(date -d "3 months ago" +%Y-%m-%d)
DROP_DATE=$(date -d "1 month ago" +%Y-%m-%d)

$MYSQL_CMD -e "INSERT INTO student_enrollment (syear, school_id, student_id, start_date, end_date, enroll_code, drop_code, grade_level) VALUES ($SYEAR, $SCHOOL_ID, $STUDENT_ID, '$START_DATE', '$DROP_DATE', '1', '2', '11');"

# Update student table to reflect current inactive status (OpenSIS often denormalizes this)
$MYSQL_CMD -e "UPDATE students SET is_disable='1' WHERE student_id='$STUDENT_ID';"

echo "Created inactive student Emily Blunt (ID: $STUDENT_ID) withdrawn on $DROP_DATE."

# 5. Record Initial State (Enrollment Count should be 1)
INITIAL_COUNT=$($MYSQL_CMD -e "SELECT COUNT(*) FROM student_enrollment WHERE student_id='$STUDENT_ID';")
echo "$INITIAL_COUNT" > /tmp/initial_enrollment_count.txt

# 6. Launch Browser
echo "Launching Chrome..."
if ! pgrep -f "chrome" > /dev/null; then
    # Determine chrome command
    if command -v google-chrome-stable &> /dev/null; then
        CHROME_CMD="google-chrome-stable"
    elif command -v chromium-browser &> /dev/null; then
        CHROME_CMD="chromium-browser"
    else
        CHROME_CMD="google-chrome"
    fi

    su - ga -c "DISPLAY=:1 $CHROME_CMD --no-sandbox --start-maximized --disable-gpu http://localhost/opensis/ &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Chrome\|Chromium"; then
            echo "Browser window found."
            break
        fi
        sleep 1
    done
    
    # Maximize and focus
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="