#!/bin/bash
echo "=== Setting up issue_written_warning task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database is ready
echo "Checking database connection..."
for i in {1..30}; do
    if opencad_db_query "SELECT 1" >/dev/null; then
        echo "Database ready."
        break
    fi
    sleep 1
done

# 3. Inject/Verify Data
# Ensure Warning Type exists
echo "Ensuring warning type 'Defective Equipment' exists..."
opencad_db_query "INSERT INTO warning_types (name) SELECT * FROM (SELECT 'Defective Equipment') AS tmp WHERE NOT EXISTS (SELECT name FROM warning_types WHERE name = 'Defective Equipment') LIMIT 1;"

# Ensure Civilian exists (Michael De Santa)
echo "Ensuring civilian 'Michael De Santa' exists..."
# Check if he exists, if not insert him into ncic_names
# Note: ncic_names is the main person table in this schema
EXISTING_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Michael De Santa' LIMIT 1")
if [ -z "$EXISTING_ID" ]; then
    opencad_db_query "INSERT INTO ncic_names (submittedByName, submittedById, name, dob, address, gender, race, dl_status, hair_color, build, weapon_permit, deceased) VALUES ('Admin User', '1A-01', 'Michael De Santa', '1968-04-01', 'Rockford Hills', 'Male', 'Caucasian', 'Valid', 'Brown', 'Average', 'Unobtained', 'NO')"
    echo "Created civilian Michael De Santa"
else
    echo "Civilian Michael De Santa already exists (ID: $EXISTING_ID)"
fi

# 4. Record Initial State
INITIAL_WARNING_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_warnings")
echo "${INITIAL_WARNING_COUNT:-0}" | sudo tee /tmp/initial_warning_count.txt > /dev/null
sudo chmod 666 /tmp/initial_warning_count.txt

# Record max ID to filter new records later
MAX_WARNING_ID=$(opencad_db_query "SELECT COALESCE(MAX(id), 0) FROM ncic_warnings")
echo "${MAX_WARNING_ID:-0}" | sudo tee /tmp/baseline_max_warning_id.txt > /dev/null
sudo chmod 666 /tmp/baseline_max_warning_id.txt

# 5. Application Setup (Firefox)
# Remove Firefox profile locks and restart
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php' &"
sleep 8

# Maximize
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="