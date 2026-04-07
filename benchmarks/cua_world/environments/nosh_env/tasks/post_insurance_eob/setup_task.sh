#!/bin/bash
set -e
echo "=== Setting up post_insurance_eob task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Database Helper Function
db_exec() {
    docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$1"
}

# 3. Clean up previous run data (if any)
echo "Cleaning up previous data..."
db_exec "DELETE FROM demographics WHERE firstname='Oliver' AND lastname='Queen';"
# Note: Cascading deletes might not be set up, so we leave orphaned billing data or rely on timestamp filtering in verification

# 4. Insert Patient: Oliver Queen
echo "Creating patient Oliver Queen..."
db_exec "INSERT INTO demographics (firstname, lastname, DOB, sex, street_address1, city, state, zip, phone_home, email, active, practice_id) VALUES ('Oliver', 'Queen', '1985-05-15', 'Male', '1 Star City Blvd', 'Star City', 'CA', '90210', '555-0199', 'oqueen@starcity.local', 1, 1);"

# Get PID
PID=$(db_exec "SELECT pid FROM demographics WHERE firstname='Oliver' AND lastname='Queen' ORDER BY pid DESC LIMIT 1;")
echo "Patient created with PID: $PID"
echo "$PID" > /tmp/patient_pid.txt

# 5. Insert Encounter (2025-03-01)
# NOSH encounters usually link to pid
echo "Creating encounter for 2025-03-01..."
db_exec "INSERT INTO encounters (pid, encounter_date, encounter_status, practice_id, provider_id) VALUES ($PID, '2025-03-01 10:00:00', 'Signed', 1, 1);"
EID=$(db_exec "SELECT eid FROM encounters WHERE pid=$PID AND encounter_date LIKE '2025-03-01%' LIMIT 1;")
echo "Encounter created with EID: $EID"

# 6. Insert Billing Charge (CPT 99214, $250.00)
# Structure of billing_core table assumed based on typical NOSH usage
echo "Creating billing charge..."
# Insert CPT code charge
db_exec "INSERT INTO billing_core (pid, eid, cpt, cpt_charge, billing_core_unit, dos, practice_id) VALUES ($PID, $EID, '99214', '250.00', 1, '2025-03-01 10:00:00', 1);"
# Insert Diagnosis (ICD) linkage
db_exec "INSERT INTO billing_core (pid, eid, icd1, dos, practice_id) VALUES ($PID, $EID, 'R51.9', '2025-03-01 10:00:00', 1);"

# 7. Record Initial Record Counts
# We count rows in billing_core/payments to detect changes
INITIAL_BILLING_COUNT=$(db_exec "SELECT COUNT(*) FROM billing_core WHERE pid=$PID;")
echo "$INITIAL_BILLING_COUNT" > /tmp/initial_billing_count.txt

# 8. Setup Browser (Login as Admin)
echo "Setting up Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to Login Page
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|nosh"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Automate Login (Admin/Admin1234!)
# Using xdotool to type credentials so agent starts at dashboard
echo "Automating login..."
sleep 3
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type "admin"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type "Admin1234!"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 5

# 10. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="