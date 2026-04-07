#!/bin/bash
set -e

echo "=== Setting up change_student_grade_level task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database Services are running
if ! systemctl is-active --quiet mariadb; then
    echo "Starting MariaDB..."
    sudo systemctl start mariadb
fi
if ! systemctl is-active --quiet apache2; then
    echo "Starting Apache..."
    sudo systemctl start apache2
fi

# 3. Setup Database State
# We need to ensure 'Marcus Williams' exists and is in Grade 9 (id=1)
# Using direct SQL for reliability
echo "Configuring database state..."

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Get School Year (SYEAR) from system or assume current
SYEAR=$(date +%Y)
if [ "$(date +%m)" -lt 8 ]; then
    SYEAR=$(date +%Y) # e.g., if Jan 2025, school year ends 2025
else
    SYEAR=$(( $(date +%Y) + 1 ))
fi

# Create/Reset Student Record
# Using INSERT ON DUPLICATE KEY UPDATE to handle re-runs
sudo mysql -u $DB_USER -p"$DB_PASS" $DB_NAME <<EOF
-- Ensure grade levels exist
INSERT INTO school_gradelevels (id, school_id, short_name, title, sort_order) VALUES
(1, 1, '9', 'Grade 9', 1),
(2, 1, '10', 'Grade 10', 2)
ON DUPLICATE KEY UPDATE title=VALUES(title);

-- Create Student (Marcus Williams)
INSERT INTO students (student_id, first_name, last_name, date_of_birth, gender, grade_level, is_disable)
VALUES (101, 'Marcus', 'Williams', '2008-05-14', 'Male', '9', 'N')
ON DUPLICATE KEY UPDATE 
    first_name='Marcus', 
    last_name='Williams', 
    grade_level='9',
    is_disable='N';

-- Ensure Enrollment Record (Grade 9)
INSERT INTO student_enrollment (id, student_id, school_id, syear, grade_id, start_date, enrollment_code, end_date)
VALUES (101, 101, 1, $SYEAR, 1, '2024-08-15', '1', NULL)
ON DUPLICATE KEY UPDATE 
    grade_id=1,
    school_id=1,
    end_date=NULL;
EOF

# Verify initial state
INITIAL_GRADE=$(sudo mysql -N -u $DB_USER -p"$DB_PASS" $DB_NAME -e "SELECT grade_id FROM student_enrollment WHERE student_id=101 LIMIT 1")
echo "$INITIAL_GRADE" > /tmp/initial_grade_id.txt
echo "Initial Grade ID: $INITIAL_GRADE"

# 4. Launch Application (Browser)
echo "Launching OpenSIS..."

# Kill existing chrome
pkill -f chrome 2>/dev/null || true

# Start Chrome pointing to OpenSIS
# We won't automate the login here to reduce setup complexity/fragility; 
# the agent description includes login instructions.
su - ga -c "DISPLAY=:1 google-chrome-stable --start-maximized --no-first-run --no-default-browser-check --password-store=basic http://localhost/opensis/ &"

# Wait for window
echo "Waiting for browser..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
        echo "Browser detected."
        break
    fi
    sleep 1
done

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# 5. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="