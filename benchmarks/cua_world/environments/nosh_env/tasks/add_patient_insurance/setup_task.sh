#!/bin/bash
set -e
echo "=== Setting up add_patient_insurance task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

NOSH_URL="http://localhost"
DB_EXEC="docker exec -i nosh-db mysql -uroot -prootpassword nosh"

# ============================================================
# Ensure patient Maria Gonzalez exists (pid will be stored)
# ============================================================
echo "Ensuring patient Maria Gonzalez exists..."

# Check if she already exists
EXISTING_PID=$(echo "SELECT pid FROM demographics WHERE firstname='Maria' AND lastname='Gonzalez' AND DOB='1978-04-12' LIMIT 1;" | $DB_EXEC -N 2>/dev/null | tr -d '[:space:]')

if [ -z "$EXISTING_PID" ] || [ "$EXISTING_PID" = "NULL" ]; then
    echo "Creating patient Maria Gonzalez..."
    
    # Find next available PID
    MAX_PID=$(echo "SELECT COALESCE(MAX(pid), 0) FROM demographics;" | $DB_EXEC -N 2>/dev/null | tr -d '[:space:]')
    NEW_PID=$((MAX_PID + 1))
    
    echo "INSERT INTO demographics (pid, firstname, lastname, DOB, sex, address, city, state, zip, phone_home, email, active, lang) VALUES ($NEW_PID, 'Maria', 'Gonzalez', '1978-04-12', 'Female', '45 Maple Avenue', 'Springfield', 'MA', '01103', '413-555-8821', 'maria.gonzalez@email.com', 1, 'English');" | $DB_EXEC 2>/dev/null
    
    # Create demographics_relate entry (links patient to practice and provider)
    echo "INSERT IGNORE INTO demographics_relate (pid, id, practice_id) VALUES ($NEW_PID, 2, 1);" | $DB_EXEC 2>/dev/null
    
    EXISTING_PID=$NEW_PID
    echo "Created patient with PID: $EXISTING_PID"
else
    echo "Patient already exists with PID: $EXISTING_PID"
fi

# Store PID for verification
echo "$EXISTING_PID" > /tmp/task_patient_pid.txt

# ============================================================
# Ensure NO existing insurance for this patient (clean state)
# ============================================================
echo "Removing any existing insurance records for this patient..."
echo "DELETE FROM insurance WHERE pid = $EXISTING_PID;" | $DB_EXEC 2>/dev/null || true

# Record initial insurance count for anti-gaming
INITIAL_INS_COUNT=$(echo "SELECT COUNT(*) FROM insurance WHERE pid = $EXISTING_PID;" | $DB_EXEC -N 2>/dev/null | tr -d '[:space:]')
echo "$INITIAL_INS_COUNT" > /tmp/initial_insurance_count.txt
echo "Initial insurance count for patient: $INITIAL_INS_COUNT"

# ============================================================
# Ensure Firefox is running and logged into NOSH
# ============================================================
echo "Setting up Firefox..."

# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Remove locks
rm -f /home/ga/.mozilla/firefox/*.default-release/lock 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock 2>/dev/null || true

# Start Firefox with NOSH login page
su - ga -c "DISPLAY=:1 firefox --no-remote '$NOSH_URL/login' &" 2>/dev/null
sleep 10

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "firefox|mozilla|nosh|login"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Log in to NOSH
echo "Logging into NOSH..."
sleep 3

# Click center to focus
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 1

# Ensure we are on login page by reloading
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "$NOSH_URL/login"
DISPLAY=:1 xdotool key Return
sleep 5

# Use keyboard to fill login form
DISPLAY=:1 xdotool key Tab
sleep 0.3
DISPLAY=:1 xdotool type "admin"
sleep 0.3
DISPLAY=:1 xdotool key Tab
sleep 0.3
DISPLAY=:1 xdotool type "Admin1234!"
sleep 0.3
DISPLAY=:1 xdotool key Return
sleep 8

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Patient PID: $EXISTING_PID"
echo "Initial insurance count: $INITIAL_INS_COUNT"