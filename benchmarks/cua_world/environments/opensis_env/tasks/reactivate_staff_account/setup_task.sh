#!/bin/bash
set -e
echo "=== Setting up Reactivate Staff Account task ==="

# 1. Start Services
echo "Ensuring services are running..."
systemctl start mariadb 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for database
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# 2. Prepare Data (Insert Inactive Staff Member)
echo "Inserting inactive staff record..."
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create the staff member "James Helper"
# We need entries in: staff, staff_school_info, login_authentication

# Get a profile ID for 'teacher' (usually 2, but let's look it up or assume 2)
# Insert into STAFF table
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME <<EOF
INSERT INTO staff (title, first_name, last_name, gender, email, profile, profile_id)
SELECT 'Mr.', 'James', 'Helper', 'Male', 'jhelper@school.edu', 'teacher', 2
WHERE NOT EXISTS (SELECT 1 FROM staff WHERE first_name='James' AND last_name='Helper');
EOF

# Get the Staff ID
STAFF_ID=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -s -e "SELECT staff_id FROM staff WHERE first_name='James' AND last_name='Helper' LIMIT 1")
echo "$STAFF_ID" > /tmp/target_staff_id.txt

# Ensure USER_ID in staff table matches staff_id (OpenSIS quirk)
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -e "UPDATE staff SET USER_ID=$STAFF_ID WHERE staff_id=$STAFF_ID"

# Insert/Update STAFF_SCHOOL_INFO to be INACTIVE (opensis_access = 'N')
# This is the critical state for the task
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME <<EOF
INSERT INTO staff_school_info (staff_id, category, home_school, opensis_access, opensis_profile, school_access)
VALUES ($STAFF_ID, 'Teacher', 1, 'N', 'teacher', 'N')
ON DUPLICATE KEY UPDATE opensis_access='N', school_access='N';
EOF

# Insert/Update LOGIN_AUTHENTICATION
# Generate a hash for 'Teacher123' if needed, or just dummy it since he's inactive
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME <<EOF
INSERT INTO login_authentication (user_id, profile_id, username, password, failed_login)
VALUES ($STAFF_ID, 2, 'jhelper', 'dummyhash', 0)
ON DUPLICATE KEY UPDATE username='jhelper';
EOF

# Link to school
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME <<EOF
INSERT INTO staff_school_relationship (staff_id, school_id, syear)
VALUES ($STAFF_ID, 1, 2025)
ON DUPLICATE KEY UPDATE staff_id=staff_id;
EOF

echo "Created inactive staff ID: $STAFF_ID"

# Record initial count of "James Helper" records (should be 1)
INITIAL_COUNT=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -s -e "SELECT COUNT(*) FROM staff WHERE first_name='James' AND last_name='Helper'")
echo "$INITIAL_COUNT" > /tmp/initial_staff_count.txt

# 3. Setup Browser
echo "Launching browser..."
if ! pgrep -f "chrome" > /dev/null; then
    su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check --start-maximized http://localhost/opensis/ &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
        echo "Browser ready."
        break
    fi
    sleep 1
done

# Focus and maximize
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="