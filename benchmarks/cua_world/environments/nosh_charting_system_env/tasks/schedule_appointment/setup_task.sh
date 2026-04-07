#!/bin/bash
set -e
echo "=== Setting up Schedule Appointment Task ==="

# 1. Record Task Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 2. Generate Dynamic Scheduling Request
# We need a real patient from the database to make this realistic.
echo "Selecting a random patient..."
# Get a random patient (PID, First, Last, DOB) - limiting to first 100 to ensure we get one
PATIENT_DATA=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT pid, firstname, lastname, DOB FROM demographics WHERE active=1 ORDER BY RAND() LIMIT 1")

if [ -z "$PATIENT_DATA" ]; then
    echo "Error: No patients found in database."
    exit 1
fi

PID=$(echo "$PATIENT_DATA" | cut -f1)
FNAME=$(echo "$PATIENT_DATA" | cut -f2)
LNAME=$(echo "$PATIENT_DATA" | cut -f3)
DOB=$(echo "$PATIENT_DATA" | cut -f4)

echo "Selected Patient: $FNAME $LNAME (PID: $PID)"

# Calculate a date: Next weekday (Mon-Fri) at least 2 days in future
# This ensures we aren't scheduling in the past or on a weekend (if closed)
TARGET_DATE=$(date -d "+3 days" +%Y-%m-%d)
DAY_OF_WEEK=$(date -d "$TARGET_DATE" +%u) # 1=Mon, 7=Sun

# If Sat(6) or Sun(7), add days to get to Monday
if [ "$DAY_OF_WEEK" -ge 6 ]; then
    TARGET_DATE=$(date -d "$TARGET_DATE + 2 days" +%Y-%m-%d)
fi

TARGET_TIME="10:00:00"
TARGET_DATETIME="$TARGET_DATE $TARGET_TIME"
DISPLAY_TIME="10:00 AM"
PROVIDER_NAME="Dr. James Carter"
VISIT_TYPE="Office Visit"

# Create the request file on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/scheduling_request.txt << EOF
SCHEDULING REQUEST
------------------
Patient Name: $FNAME $LNAME
Date of Birth: $DOB
Provider: $PROVIDER_NAME
Date: $TARGET_DATE
Time: $DISPLAY_TIME
Visit Type: $VISIT_TYPE

Please schedule this appointment in the system.
EOF

chmod 644 /home/ga/Desktop/scheduling_request.txt

# 3. Save Expected Data for Verification
# We save these to /tmp so export_result.sh can read them later
echo "$PID" > /tmp/expected_pid.txt
echo "$TARGET_DATETIME" > /tmp/expected_datetime.txt
echo "$PROVIDER_NAME" > /tmp/expected_provider.txt
echo "$VISIT_TYPE" > /tmp/expected_visittype.txt
echo "Expected values saved to /tmp."

# 4. Record Initial Schedule State
# Count appointments to detect if anything changes
INITIAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM schedule")
echo "$INITIAL_COUNT" > /tmp/initial_schedule_count.txt

# 5. Prepare Browser
# Kill existing instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean locks
find /home/ga/.mozilla/firefox -name "*.lock" -delete 2>/dev/null || true

# Start Firefox at Login Page
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        echo "Firefox window found."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Patient: $FNAME $LNAME"
echo "Target: $TARGET_DATE at $DISPLAY_TIME"