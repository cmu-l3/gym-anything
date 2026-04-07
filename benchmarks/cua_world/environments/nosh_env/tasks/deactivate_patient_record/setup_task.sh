#!/bin/bash
set -e
echo "=== Setting up deactivate_patient_record task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Database Readiness
echo "Checking database..."
MAX_RETRIES=30
for i in $(seq 1 $MAX_RETRIES); do
    if docker exec nosh-db mysqladmin ping -h localhost -uroot -prootpassword --silent; then
        echo "Database is ready."
        break
    fi
    echo "Waiting for database... ($i/$MAX_RETRIES)"
    sleep 2
done

# 2. Ensure Target Patient Exists and is ACTIVE
echo "Preparing target patient data..."
# Check if patient exists
PATIENT_CHECK=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT pid FROM demographics WHERE lastname='Schiller' AND firstname='Robert' AND DOB='1965-09-14';" 2>/dev/null)

if [ -z "$PATIENT_CHECK" ]; then
    echo "Inserting patient Robert Schiller..."
    # Insert demographic
    docker exec nosh-db mysql -uroot -prootpassword nosh -e \
        "INSERT INTO demographics (lastname, firstname, DOB, sex, active, practice_id) VALUES ('Schiller', 'Robert', '1965-09-14', 'Male', 1, 1);"
    
    # Get new PID
    NEW_PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
        "SELECT pid FROM demographics WHERE lastname='Schiller' AND firstname='Robert' AND DOB='1965-09-14';")
    
    # Associate with provider (admin/provider)
    docker exec nosh-db mysql -uroot -prootpassword nosh -e \
        "INSERT IGNORE INTO demographics_relate (pid, id, practice_id) VALUES ($NEW_PID, 2, 1);"
else
    # Ensure patient is active
    echo "Ensuring patient is active..."
    docker exec nosh-db mysql -uroot -prootpassword nosh -e \
        "UPDATE demographics SET active=1 WHERE lastname='Schiller' AND firstname='Robert' AND DOB='1965-09-14';"
fi

# 3. Record Initial State for Verification
TARGET_PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT pid FROM demographics WHERE lastname='Schiller' AND firstname='Robert' AND DOB='1965-09-14' LIMIT 1;" | tr -d '[:space:]')
echo "$TARGET_PID" > /tmp/target_pid.txt

INITIAL_ACTIVE_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM demographics WHERE active=1;" | tr -d '[:space:]')
echo "$INITIAL_ACTIVE_COUNT" > /tmp/initial_active_count.txt

echo "Target PID: $TARGET_PID"
echo "Initial Active Count: $INITIAL_ACTIVE_COUNT"

# 4. Prepare Browser
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 1

# Clean profile cleanup to avoid recovery dialogs
rm -rf /home/ga/.mozilla/firefox/*.default-release/sessionstore.js* 2>/dev/null || true

# Launch
su - ga -c "DISPLAY=:1 firefox --new-instance http://localhost/login &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 5. Automate Login (Optional but helpful for 'logged in' start state)
# We will just focus the window and let the agent log in as per description "Log in as admin..."
# But we ensure the field is ready
sleep 2
DISPLAY=:1 xdotool key F5
sleep 3

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="