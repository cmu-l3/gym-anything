#!/bin/bash
set -e
echo "=== Setting up Edit Medication Dosage Task ==="

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Database Setup: Ensure Patient and Medication Exist
# We use docker exec to interact with the nosh-db container
echo "Preparing database state..."

# Ensure Maria Gonzalez (pid=3) exists (relying on standard env data, but verifying)
PATIENT_CHECK=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT count(*) FROM demographics WHERE pid=3;" 2>/dev/null)
if [ "$PATIENT_CHECK" -eq "0" ]; then
    echo "Inserting patient Maria Gonzalez..."
    docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "INSERT INTO demographics (pid, firstname, lastname, DOB, sex, address, city, state, zip, phone_home, email, active, practice_id) \
     VALUES (3, 'Maria', 'Gonzalez', '1962-08-15', 'Female', '123 Arbor Ln', 'Springfield', 'MA', '01104', '413-555-0199', 'maria.g@example.com', 1, 1);"
fi

# Reset Medication State: Remove any existing Lisinopril for this patient to ensure clean slate
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM rx_list WHERE pid=3 AND rxl_medication LIKE '%Lisinopril%';"

# Insert the TARGET medication (Starting State: 10mg, once daily)
echo "Inserting starting medication record..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "INSERT INTO rx_list (rxl_medication, rxl_dosage, rxl_sig, rxl_route, rxl_frequency, rxl_quantity, rxl_refill, rxl_date_active, rxl_date_prescribed, pid, practice_id) \
     VALUES ('Lisinopril', '10 mg', 'Take 10 mg by mouth once daily', 'by mouth', 'once daily', '30', '3', NOW(), NOW(), 3, 1);"

# Capture the ID of the inserted record for verification later
INITIAL_ID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT rxl_id FROM rx_list WHERE pid=3 AND rxl_medication LIKE '%Lisinopril%' ORDER BY rxl_id DESC LIMIT 1;")
echo "$INITIAL_ID" > /tmp/initial_med_id.txt
echo "Created Lisinopril record ID: $INITIAL_ID"

# 3. Browser Setup
echo "Configuring Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 1

# Clean profile locks
rm -f /home/ga/.mozilla/firefox/*.default-release/lock
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock

# Start Firefox
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' &"

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
sleep 2

# 4. Automate Login (Agent starts logged in)
echo "Automating login..."
# Focus window
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1

# Type credentials (admin / Admin1234!)
# Tab to username field (usually focused by default, but ensuring)
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
# Cycle back to ensure focus
DISPLAY=:1 xdotool key Shift+Tab
DISPLAY=:1 xdotool key Shift+Tab

# Type Username
DISPLAY=:1 xdotool type "admin"
DISPLAY=:1 xdotool key Tab
sleep 0.5
# Type Password
DISPLAY=:1 xdotool type "Admin1234!"
DISPLAY=:1 xdotool key Return
sleep 5

# Handle "Practice ID" selection if it appears (sometimes it does on first login)
# We wait to see if we are redirected. If still on login or intermediate page, try pressing Enter again.
DISPLAY=:1 xdotool key Return
sleep 5

# 5. Capture Initial Evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="