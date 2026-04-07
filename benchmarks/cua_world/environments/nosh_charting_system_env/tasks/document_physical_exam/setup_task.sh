#!/bin/bash
set -e
echo "=== Setting up document_physical_exam task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Database Setup - Ensure Patient and Encounter Exist
echo "Configuring database state..."

# Define IDs
PID=99
EID=200
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%s)

# Helper for SQL execution
run_sql() {
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "$1" 2>/dev/null
}

# Clean up any previous attempts for this specific encounter
run_sql "DELETE FROM pe WHERE eid=${EID};"
run_sql "DELETE FROM encounters WHERE eid=${EID};"
run_sql "DELETE FROM demographics WHERE pid=${PID};"

# Insert Patient: Robert Thompson
echo "Creating patient Robert Thompson..."
run_sql "INSERT INTO demographics (pid, firstname, lastname, DOB, sex, active, address, city, state, zip, phone_home, email) VALUES (${PID}, 'Robert', 'Thompson', '1958-07-22', 'm', 1, '45 Oak Avenue', 'Springfield', 'MA', '01103', '413-555-9876', 'robert.thompson@example.com');"
run_sql "INSERT INTO demographics_relate (pid, id, practice_id) VALUES (${PID}, 2, 1);"

# Insert Encounter: Today
echo "Creating encounter for today..."
# Note: encounter_provider=2 (demo_provider), encounter_signed='No'
run_sql "INSERT INTO encounters (eid, pid, encounter_provider, encounter_DOS, encounter_type, encounter_signed, practice_id, encounter_role, encounter_template, encounter_cc, addendum, user_id) VALUES (${EID}, ${PID}, '2', '${TODAY}', 'Office Visit', 'No', 1, 'provider', 'standardmedical', 'Routine health maintenance examination', 'n', 2);"

# Record initial PE count (should be 0 for this encounter)
INITIAL_PE_COUNT=$(run_sql "SELECT COUNT(*) FROM pe WHERE eid=${EID}" -N)
echo "$INITIAL_PE_COUNT" > /tmp/initial_pe_count.txt
echo "Initial PE records: $INITIAL_PE_COUNT"

# 3. Browser Setup
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean profiles to avoid lock issues
rm -f /home/ga/.mozilla/firefox/*.default-release/lock
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock

# Launch Firefox to login page
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox\|Mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 4. Evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="