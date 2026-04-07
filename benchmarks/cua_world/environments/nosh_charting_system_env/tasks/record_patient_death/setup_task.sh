#!/bin/bash
set -e
echo "=== Setting up Record Patient Death Task ==="

# 1. Define Patient Data
PATIENT_FNAME="Albert"
PATIENT_LNAME="Zweig"
PATIENT_DOB="1955-03-12"
DEATH_DATE="2025-11-30"
NOTIFICATION_FILE="/home/ga/Desktop/coroner_notification.txt"

# 2. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Prepare Database State
# Ensure the patient exists and is currently ALIVE (deceased_date IS NULL)
# We use docker exec to run SQL against the nosh-db container
echo "Resetting patient record in database..."

# Delete if exists to ensure clean state (avoids duplicate logic complexity)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM demographics WHERE firstname='$PATIENT_FNAME' AND lastname='$PATIENT_LNAME';" 2>/dev/null || true

# Insert patient (Active, Alive)
# Note: NOSH demographics schema varies, but minimal insert usually works.
# pid is auto-increment.
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "INSERT INTO demographics (firstname, lastname, DOB, sex, active) VALUES ('$PATIENT_FNAME', '$PATIENT_LNAME', '$PATIENT_DOB', 'Male', 1);"

# Get the PID for reference
PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT pid FROM demographics WHERE firstname='$PATIENT_FNAME' AND lastname='$PATIENT_LNAME' LIMIT 1;")
echo "Target Patient PID: $PID" > /tmp/target_pid.txt

# 4. Create Notification File
echo "Creating notification file..."
cat > "$NOTIFICATION_FILE" << EOF
CORONER'S OFFICE - MORTALITY NOTIFICATION
-----------------------------------------
Date: $(date +%F)

To: Practice Manager, Hillside Family Medicine

Re: Notification of Patient Decease

This memo serves as official notification that the following individual has passed away.
Please update your records accordingly.

Patient Name:  $PATIENT_FNAME $PATIENT_LNAME
Date of Birth: $PATIENT_DOB
Date of Death: $DEATH_DATE
Cause:         Natural Causes

Signed,
County Coroner
EOF

chmod 644 "$NOTIFICATION_FILE"
chown ga:ga "$NOTIFICATION_FILE"

# 5. Launch Application (Firefox) to Login Page
echo "Launching Firefox..."
# Kill any existing instances
pkill -f firefox || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox http://localhost/login &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="