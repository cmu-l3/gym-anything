#!/bin/bash
set -e
echo "=== Setting up Withdraw Student Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for MariaDB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# ============================================================================
# DATA PREPARATION
# ============================================================================

# 1. Ensure School Year 2024-2025 exists (to match the task date 2025-01-15)
echo "Configuring school year..."
$MYSQL_CMD -e "
INSERT INTO school_years (marking_period_id, syear, school_id, title, short_name, sort_order, start_date, end_date, does_grades, does_comments)
VALUES (1, 2025, 1, '2024-2025', 'FY', 1, '2024-08-01', '2025-06-30', 'Y', 'Y')
ON DUPLICATE KEY UPDATE start_date='2024-08-01', end_date='2025-06-30';
" 2>/dev/null

# 2. Insert Enrollment Codes (Ensure 'Transferred' exists)
echo "Inserting enrollment codes..."
$MYSQL_CMD -e "
INSERT INTO student_enrollment_codes (id, syear, school_id, title, short_name, type, sort_order) VALUES
(101, 2025, 1, 'New Enrollment', 'NEW', 'Add', 1),
(201, 2025, 1, 'Transferred', 'TRANS', 'Drop', 1),
(202, 2025, 1, 'Expelled', 'EXP', 'Drop', 2),
(203, 2025, 1, 'Graduated', 'GRAD', 'Drop', 3)
ON DUPLICATE KEY UPDATE title=VALUES(title), type=VALUES(type);
" 2>/dev/null

# 3. Insert Student 'Maria Rodriguez'
echo "Inserting student record..."
# Clean up potential duplicates first to ensure clean state
$MYSQL_CMD -e "DELETE FROM students WHERE first_name='Maria' AND last_name='Rodriguez';" 2>/dev/null || true
$MYSQL_CMD -e "
INSERT INTO students (student_id, first_name, last_name, middle_name, date_of_birth, gender, ethnicity, common_name, grade_level)
VALUES (990, 'Maria', 'Rodriguez', 'Elena', '2009-05-22', 'Female', 'Hispanic', 'Maria', '10');
" 2>/dev/null

# 4. Insert ACTIVE Enrollment (end_date IS NULL)
echo "Creating active enrollment..."
$MYSQL_CMD -e "DELETE FROM student_enrollment WHERE student_id=990;" 2>/dev/null || true
$MYSQL_CMD -e "
INSERT INTO student_enrollment (id, syear, school_id, student_id, grade_id, start_date, end_date, enrollment_code, drop_code)
VALUES (990, 2025, 1, 990, 2, '2024-08-15', NULL, 101, NULL);
" 2>/dev/null

# Record Initial State for Anti-Gaming
# We record that end_date is NULL and drop_code is NULL
INITIAL_STATE_JSON=$(cat <<EOF
{
    "student_id": 990,
    "initial_end_date": null,
    "initial_drop_code": null,
    "setup_timestamp": $(date +%s)
}
EOF
)
echo "$INITIAL_STATE_JSON" > /tmp/initial_state.json

# ============================================================================
# BROWSER SETUP
# ============================================================================

# Launch Chrome with OpenSIS
echo "Launching Chrome..."
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

su - ga -c "DISPLAY=:1 google-chrome-stable \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --no-first-run \
    --no-default-browser-check \
    --disable-infobars \
    --password-store=basic \
    --start-maximized \
    'http://localhost/opensis/' &" 2>/dev/null

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "chrome|chromium|opensis"; then
        echo "Chrome window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="