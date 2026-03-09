#!/bin/bash
set -e
echo "=== Setting up record_vitals task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
# Also in SQL format for easier DB comparison
date -u '+%Y-%m-%d %H:%M:%S' > /tmp/task_start_time_mysql.txt

# Wait for Oscar to be ready
wait_for_oscar_http 180

# 1. Ensure Provider exists (oscardoc / 999998)
echo "Ensuring provider exists..."
oscar_query "INSERT IGNORE INTO provider (provider_no, last_name, first_name, provider_type, sex, specialty, status, ohip_no) VALUES ('999998', 'Chen', 'Sarah', 'doctor', 'F', '00', '1', '999998');"

# 2. Check/Create Patient Maria Santos
echo "Checking for patient Maria Santos..."
EXISTING_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' AND year_of_birth='1978' LIMIT 1")

if [ -z "$EXISTING_ID" ]; then
    echo "Creating patient Maria Santos..."
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
        hin, ver, province, address, city, postal, phone,
        patient_status, provider_no, family_doctor, date_joined
    ) VALUES (
        'Santos', 'Maria', 'F', '1978', '06', '22',
        '6128445790', 'AB', 'ON', '45 Lakeshore Blvd', 'Toronto', 'M5V 1A1', '416-555-0193',
        'AC', '999998', 'Dr. Sarah Chen', NOW()
    );"
    
    # Get the new ID
    EXISTING_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' ORDER BY demographic_no DESC LIMIT 1")
    
    # Create admission record (required for some e-chart views)
    oscar_query "INSERT INTO admission (client_id, admission_status, program_id, provider_no, admission_date) VALUES ('$EXISTING_ID', 'current', 1, '999998', NOW());"
fi

echo "$EXISTING_ID" > /tmp/maria_santos_id.txt
echo "Maria Santos demographic_no: $EXISTING_ID"

# 3. Clean up any existing measurements for this patient (fresh start for this task)
# In a real scenario we might append, but for verification simplicity we prefer a known baseline.
# However, to be "realistic", we shouldn't wipe data if we can avoid it. 
# Instead, we will count existing records.
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM measurements WHERE demographicNo='$EXISTING_ID'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_measurement_count.txt
echo "Initial measurement count: $INITIAL_COUNT"

# 4. Start Firefox on Login Page
ensure_firefox_on_oscar

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="