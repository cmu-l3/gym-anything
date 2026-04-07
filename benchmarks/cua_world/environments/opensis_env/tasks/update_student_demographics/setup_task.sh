#!/bin/bash
set -e

echo "=== Setting up Update Student Demographics Task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Start Services
echo "Starting services..."
service mariadb start || true
service apache2 start || true

# Wait for DB to be ready
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# 3. Prepare Database State
# We need to insert the student with OLD data
echo "Preparing database records..."

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# SQL to reset/insert the specific student
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Clean up if exists
DELETE FROM student_enrollment WHERE student_id = 100;
DELETE FROM students WHERE student_id = 100;

-- Insert Student with OLD address/contact info
INSERT INTO students (
    student_id, first_name, middle_name, last_name, 
    date_of_birth, gender, ethnicity, 
    address, city, state, zipcode, 
    phone, email, grade_id
) VALUES (
    100, 'Maria', 'Elena', 'Rodriguez', 
    '2006-05-14', 'Female', 'Hispanic or Latino', 
    '456 Oak Avenue', 'Springfield', 'IL', '62701', 
    '217-555-0142', 'maria.rodriguez@oldmail.com', 2
);

-- Insert Enrollment so she shows up in search
-- Assuming School ID 1 and current SYEAR from system or default
INSERT INTO student_enrollment (
    student_id, school_id, syear, grade_id, start_date, enrollment_code
) VALUES (
    100, 1, 2025, 2, '2024-08-15', 'New'
);
EOF

# 4. Record Initial State for Debugging
echo "Initial record state:"
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT address, email FROM students WHERE student_id=100;"

# 5. Launch Application
echo "Launching Chrome..."
# Kill existing instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

# Determine browser command
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser" # Fallback
fi

# Launch
su - ga -c "DISPLAY=:1 $CHROME_CMD --no-first-run --no-default-browser-check --start-maximized --password-store=basic http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenSIS"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "OpenSIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenSIS" 2>/dev/null || true

# 6. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="