#!/bin/bash
set -e
echo "=== Setting up Merge Duplicate Patients Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OSCAR to be ready
wait_for_oscar_http 300

# Clean up any previous task data (idempotency)
echo "Cleaning up previous data..."
oscar_query "DELETE FROM demographic WHERE demographic_no IN (10001, 10002);" 2>/dev/null || true
oscar_query "DELETE FROM admission WHERE client_id IN (10001, 10002);" 2>/dev/null || true
oscar_query "DELETE FROM allergies WHERE demographic_no IN ('10001', '10002');" 2>/dev/null || true
oscar_query "DELETE FROM demographic_merged WHERE demographic_no IN (10001, 10002) OR merged_to IN (10001, 10002);" 2>/dev/null || true

# 1. Create PRIMARY patient record (to KEEP) - ID 10001
echo "Creating primary patient (10001)..."
oscar_query "INSERT INTO demographic (demographic_no, last_name, first_name, sex, date_of_birth,
    hin, ver, address, city, province, postal, phone, patient_status,
    provider_no, roster_status, date_joined, year_of_birth, month_of_birth,
    family_doctor, chart_no, email, lastUpdateDate)
    VALUES (10001, 'Smith', 'Robert James', 'M', '1965-05-20',
    '1234567890', 'AB', '45 Maple Drive', 'Toronto', 'ON', 'M5V 2T6',
    '416-555-0123', 'AC', '999998', 'RO', CURDATE(), '1965', '05',
    '<rdohip>999998</rdohip><rd>Smith, Robert James</rd>', 'RS10001',
    'robert.smith@email.com', NOW());"

# 2. Create DUPLICATE patient record (to MERGE) - ID 10002
echo "Creating duplicate patient (10002)..."
oscar_query "INSERT INTO demographic (demographic_no, last_name, first_name, sex, date_of_birth,
    hin, ver, address, city, province, postal, phone, patient_status,
    provider_no, roster_status, date_joined, year_of_birth, month_of_birth,
    family_doctor, chart_no, email, lastUpdateDate)
    VALUES (10002, 'Smith', 'Rob J', 'M', '1965-05-20',
    '1234567890', 'AB', '45 Maple Dr', 'Toronto', 'ON', 'M5V2T6',
    '416-555-0124', 'AC', '999998', 'RO', CURDATE(), '1965', '05',
    '<rdohip>999998</rdohip><rd>Smith, Rob J</rd>', 'RS10002',
    'rsmith65@gmail.com', NOW());"

# 3. Add clinical data to duplicate (Allergy) to test data transfer
echo "Adding allergy to duplicate record..."
oscar_query "INSERT INTO allergies (demographic_no, description, TypeCode, reaction, 
    entry_date, start_date, archived)
    VALUES ('10002', 'PENICILLIN', '13', 'Rash and hives',
    CURDATE(), CURDATE(), '0');" 2>/dev/null || true

# 4. Add admission records (required for chart access in some Oscar versions)
oscar_query "INSERT IGNORE INTO admission (client_id, admission_date, program_id, provider_no, 
    admission_status, team_id)
    VALUES (10001, NOW(), (SELECT program_id FROM program WHERE name='OSCAR' LIMIT 1), '999998', 
    'current', 0);" 2>/dev/null || true
oscar_query "INSERT IGNORE INTO admission (client_id, admission_date, program_id, provider_no, 
    admission_status, team_id)
    VALUES (10002, NOW(), (SELECT program_id FROM program WHERE name='OSCAR' LIMIT 1), '999998', 
    'current', 0);" 2>/dev/null || true

# Record initial state values for verification
echo "Recording initial state..."
INITIAL_STATUS_10001=$(oscar_query "SELECT patient_status FROM demographic WHERE demographic_no=10001")
INITIAL_STATUS_10002=$(oscar_query "SELECT patient_status FROM demographic WHERE demographic_no=10002")
ACTIVE_SMITH_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE last_name='Smith' AND date_of_birth='1965-05-20' AND patient_status='AC'")

# Save to temp file (for export script if needed, though mostly we check final state)
cat > /tmp/initial_state.json << EOF
{
    "status_10001": "$INITIAL_STATUS_10001",
    "status_10002": "$INITIAL_STATUS_10002",
    "active_count": $ACTIVE_SMITH_COUNT
}
EOF

echo "Initial State: 10001=$INITIAL_STATUS_10001, 10002=$INITIAL_STATUS_10002, Active Count=$ACTIVE_SMITH_COUNT"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="