#!/bin/bash
set -e
echo "=== Setting up Revoke Staff Access task ==="

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
sleep 2
systemctl start apache2 2>/dev/null || true
sleep 2

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p'$DB_PASS' $DB_NAME"

# Get School ID (usually 1)
SCHOOL_ID=$($MYSQL_CMD -N -e "SELECT id FROM schools LIMIT 1" 2>/dev/null || echo "1")
SYEAR=$($MYSQL_CMD -N -e "SELECT syear FROM schools WHERE id=$SCHOOL_ID" 2>/dev/null || echo "2025")

echo "Creating target staff member: Gerald Fitzpatrick..."

# Clean up if exists to ensure clean state
$MYSQL_CMD -e "DELETE FROM login_authentication WHERE username='gfitz';" 2>/dev/null || true
$MYSQL_CMD -e "DELETE ssi FROM staff_school_info ssi JOIN staff s ON ssi.staff_id = s.staff_id WHERE s.first_name='Gerald' AND s.last_name='Fitzpatrick';" 2>/dev/null || true
$MYSQL_CMD -e "DELETE ssr FROM staff_school_relationship ssr JOIN staff s ON ssr.staff_id = s.staff_id WHERE s.first_name='Gerald' AND s.last_name='Fitzpatrick';" 2>/dev/null || true
$MYSQL_CMD -e "DELETE FROM staff WHERE first_name='Gerald' AND last_name='Fitzpatrick';" 2>/dev/null || true

# Insert Staff Record (Use high ID to avoid conflicts)
# Note: profile_id 2 is usually Teacher
$MYSQL_CMD << EOF
INSERT INTO staff (staff_id, current_school_id, title, first_name, last_name, gender, email, profile, profile_id) 
VALUES (9999, $SCHOOL_ID, 'Mr.', 'Gerald', 'Fitzpatrick', 'Male', 'g.fitz@demoschool.edu', 'teacher', 2);

-- Link User ID (Self-referential in OpenSIS often)
UPDATE staff SET USER_ID = 9999 WHERE staff_id = 9999;

-- Insert Staff School Info (CRITICAL: opensis_access = 'Y' initially)
INSERT INTO staff_school_info (staff_id, category, home_school, opensis_access, opensis_profile, school_access) 
VALUES (9999, 'Teacher', $SCHOOL_ID, 'Y', 'teacher', 'Y');

-- Insert Relationship for current year
INSERT INTO staff_school_relationship (staff_id, school_id, syear) 
VALUES (9999, $SCHOOL_ID, $SYEAR);

-- Create Login Credentials
INSERT INTO login_authentication (user_id, profile_id, username, password, failed_login) 
VALUES (9999, 2, 'gfitz', 'Teacher123', 0);
EOF

echo "Gerald Fitzpatrick created with active access (opensis_access='Y')."

# Save initial state for comparison
echo "Y" > /tmp/initial_access_state.txt
echo "1" > /tmp/initial_user_count.txt

# Ensure Chrome is running and ready for the agent
# Kill any existing Chrome instances
pkill -f chrome 2>/dev/null || true
sleep 1

# Start Chrome pointing to OpenSIS
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="google-chrome" # Fallback
fi

echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 $CHROME_CMD --no-sandbox --start-maximized --disable-gpu http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Focus and maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="