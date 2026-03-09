#!/bin/bash
set -e
echo "=== Setting up discontinue_medication task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time and date for verification
date +%s > /tmp/task_start_timestamp.txt
date +%Y-%m-%d > /tmp/task_start_date.txt

# Ensure OSCAR is reachable
wait_for_oscar_http 180

# 1. Setup Patient: Margaret Thompson
echo "Checking for patient Margaret Thompson..."
PATIENT_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Margaret' AND last_name='Thompson' AND year_of_birth='1958'" | tr -d '[:space:]')

if [ "${PATIENT_EXISTS:-0}" -lt 1 ]; then
    echo "Creating patient Margaret Thompson..."
    # Insert patient
    oscar_query "
    INSERT INTO demographic (
        last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
        hin, ver, address, city, province, postal, phone,
        patient_status, roster_status, provider_no, family_doctor,
        date_joined, chart_no, official_lang, lastUpdateDate
    ) VALUES (
        'Thompson', 'Margaret', 'F', '1958', '07', '22',
        '9876543217', 'AB', '45 Elm Street', 'Toronto', 'ON', 'M4W1A1', '416-555-0198',
        'AC', 'RO', '999998', '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>',
        CURDATE(), 'MT20001', 'English', NOW()
    );"
else
    echo "Patient Margaret Thompson already exists."
fi

# Get demographic_no
DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Margaret' AND last_name='Thompson' AND year_of_birth='1958' LIMIT 1" | tr -d '[:space:]')
echo "$DEMO_NO" > /tmp/task_patient_demo_no.txt
echo "Patient ID: $DEMO_NO"

# 2. Clean State: Remove any existing Metformin records for this patient
# We want a single clean active prescription to start
echo "Cleaning up old medication records..."
oscar_query "DELETE FROM drugs WHERE demographic_no='$DEMO_NO' AND (BN LIKE '%METFORMIN%' OR GN LIKE '%metformin%');" 2>/dev/null || true

# 3. Insert Active Prescription: Metformin 500mg
# Set start date 6 months ago, end date 6 months future
# archived=0 means active
echo "Inserting active Metformin prescription..."
oscar_query "
INSERT INTO drugs (
    provider_no, demographic_no, rx_date, end_date,
    BN, GN, regional_identifier,
    unit, method, route, drug_form, dosage,
    freqcode, duration, durunit, quantity,
    repeat_drug, last_refill_date,
    special, special_instruction,
    archived, archived_date, archivedReason,
    past_med, long_term, patient_compliance,
    outside_provider_name, outside_provider_ohip,
    custom_name, created_at, updated_at
) VALUES (
    '999998', '$DEMO_NO', DATE_SUB(CURDATE(), INTERVAL 180 DAY), DATE_ADD(CURDATE(), INTERVAL 180 DAY),
    'METFORMIN', 'metformin HCl', '02242829',
    'mg', 'Take', 'PO', 'TAB', '500',
    'BID', '365', 'D', '180',
    6, DATE_SUB(CURDATE(), INTERVAL 30 DAY),
    'METFORMIN 500 mg PO BID', 'Take with meals to reduce GI upset',
    0, NULL, NULL,
    0, 1, NULL,
    '', '',
    0, NOW(), NOW()
);"

# 4. Get and record the specific Drug ID for verification
DRUG_ID=$(oscar_query "SELECT drugid FROM drugs WHERE demographic_no='$DEMO_NO' AND (BN LIKE '%METFORMIN%' OR GN LIKE '%metformin%') AND archived=0 ORDER BY drugid DESC LIMIT 1" | tr -d '[:space:]')
echo "$DRUG_ID" > /tmp/task_drug_id.txt
echo "Target Drug ID: $DRUG_ID"

# Record initial archived state (should be 0)
INITIAL_ARCHIVED=$(oscar_query "SELECT archived FROM drugs WHERE drugid='$DRUG_ID'" | tr -d '[:space:]')
echo "$INITIAL_ARCHIVED" > /tmp/task_initial_archived.txt

# 5. Launch Application
echo "Launching Firefox on OSCAR..."
ensure_firefox_on_oscar

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="