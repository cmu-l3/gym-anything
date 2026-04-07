#!/bin/bash
set -e

echo "=== Setting up generate_absence_report task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous artifacts
rm -f /home/ga/Documents/absence_report.pdf
rm -f /home/ga/Downloads/*.pdf

# 3. Database & Data Setup
# We need to inject:
# - 3 Students
# - Attendance records for TODAY
#   * Cameron Frye: Absent
#   * Ferris Bueller: Absent
#   * Hermione Granger: Present

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
TODAY=$(date +%Y-%m-%d)
SYEAR=$(date +%Y)

# Helper for SQL execution
run_sql() {
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "$1" 2>/dev/null
}

echo "Injecting test data..."

# Ensure Attendance Codes exist (A=Absent, P=Present)
run_sql "INSERT INTO attendance_codes (school_id, title, short_name, type, state_code, sort_order) VALUES (1, 'Absent', 'A', '0', 'A', 1) ON DUPLICATE KEY UPDATE title='Absent';"
run_sql "INSERT INTO attendance_codes (school_id, title, short_name, type, state_code, sort_order) VALUES (1, 'Present', 'P', '1', 'P', 2) ON DUPLICATE KEY UPDATE title='Present';"

# Get Code IDs (assuming ID autoincrement, but let's try to be safe)
# For simplicity in this script, we'll use the short_name in the attendance table if the schema allows,
# or we just rely on standard OpenSIS behavior where 'A' and 'P' are often defaults.
# However, the attendance table usually links to code IDs or uses the code directly.
# Let's check schema assumptions: usually `attendance_code` or `status`.
# We will insert students first.

# Function to create student and get ID
create_student() {
    local first=$1
    local last=$2
    run_sql "INSERT INTO students (first_name, last_name, gender, date_of_birth, grade_level, school_id) SELECT '$first', '$last', 'M', '2005-01-01', '12', 1 WHERE NOT EXISTS (SELECT 1 FROM students WHERE first_name='$first' AND last_name='$last');"
    # Return the ID
    run_sql "SELECT student_id FROM students WHERE first_name='$first' AND last_name='$last' LIMIT 1;" | tail -n 1
}

CAMERON_ID=$(create_student "Cameron" "Frye")
FERRIS_ID=$(create_student "Ferris" "Bueller")
HERMIONE_ID=$(create_student "Hermione" "Granger")

echo "Student IDs: Cameron=$CAMERON_ID, Ferris=$FERRIS_ID, Hermione=$HERMIONE_ID"

# Insert Attendance for Today
# Note: Schema for `attendance` often requires: student_id, school_id, syear, attendance_date, attendance_code/status
# We'll try a standard insert. If `attendance_period` is required, we assume period 1 or default.

insert_attendance() {
    local sid=$1
    local code=$2
    local comment=$3
    # Delete existing for today to avoid dupes
    run_sql "DELETE FROM attendance WHERE student_id='$sid' AND attendance_date='$TODAY';"
    
    # Attempt insert (adjusting for common OpenSIS schema variations)
    # V9.x often uses 'attendance_code'
    run_sql "INSERT INTO attendance (student_id, school_id, syear, attendance_date, attendance_code, comment) VALUES ('$sid', 1, $SYEAR, '$TODAY', '$code', '$comment');"
}

insert_attendance "$CAMERON_ID" "A" "Sick"
insert_attendance "$FERRIS_ID" "A" "Skipping"
insert_attendance "$HERMIONE_ID" "P" "Present"

echo "Attendance data injected."

# 4. Prepare Browser
# Kill existing chrome
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

# Start Chrome on OpenSIS Login
if command -v google-chrome-stable &> /dev/null; then
    BROWSER="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    BROWSER="chromium-browser"
else
    BROWSER="chrome-browser"
fi

echo "Starting browser..."
su - ga -c "DISPLAY=:1 $BROWSER --no-first-run --no-default-browser-check --password-store=basic --start-maximized http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        echo "Browser window detected."
        break
    fi
    sleep 1
done

# Ensure maximized
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="