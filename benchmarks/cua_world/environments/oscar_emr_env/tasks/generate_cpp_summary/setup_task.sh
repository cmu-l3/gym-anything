#!/bin/bash
set -e
echo "=== Setting up Generate CPP Summary task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for file timestamp verification)
date +%s > /tmp/task_start_time.txt

# Clean downloads folder to ensure we identify the correct new file
rm -f /home/ga/Downloads/*.pdf
mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads

# Ensure OSCAR is ready
wait_for_oscar_http 180

# ============================================================
# 1. Create Patient "Oliver Export"
# ============================================================
echo "Ensuring patient Oliver Export exists..."
PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Oliver' AND last_name='Export' LIMIT 1")

if [ -z "$PATIENT_ID" ]; then
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, year_of_birth, month_of_birth, date_of_birth_day,
        hin, ver, province, address, city, postal,
        phone, patient_status, date_joined, chart_no,
        provider_no, family_doctor
    ) VALUES (
        'Export', 'Oliver', 'M', '1980-05-15', '1980', '05', '15',
        '9988776655', 'ON', 'ON', '123 Export Lane', 'Toronto', 'M5V 2H1',
        '416-555-0199', 'AC', CURDATE(), '95001',
        '999998', '999998'
    );"
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Oliver' AND last_name='Export' LIMIT 1")
    echo "Created Oliver Export with ID: $PATIENT_ID"
else
    echo "Patient Oliver Export already exists (ID: $PATIENT_ID)"
fi

# ============================================================
# 2. Add Clinical Data (Allergies & Problems)
# ============================================================

# Add Allergy: Penicillin
# Check if exists first to avoid duplicates
ALLERGY_COUNT=$(oscar_query "SELECT COUNT(*) FROM allergies WHERE demographic_no='$PATIENT_ID' AND description LIKE '%Penicillin%'")
if [ "${ALLERGY_COUNT:-0}" -eq 0 ]; then
    echo "Adding Penicillin allergy..."
    oscar_query "INSERT INTO allergies (
        demographic_no, description, reaction, entry_date, provider_no, archived, severe_code
    ) VALUES (
        '$PATIENT_ID', 'Penicillin', 'Hives', NOW(), '999998', 0, 'MI'
    );"
fi

# Add Disease Registry / Problem: Asthma (ICD9 493)
DX_COUNT=$(oscar_query "SELECT COUNT(*) FROM dxresearch WHERE demographic_no='$PATIENT_ID' AND dx_research_code='493'")
if [ "${DX_COUNT:-0}" -eq 0 ]; then
    echo "Adding Asthma problem..."
    oscar_query "INSERT INTO dxresearch (
        demographic_no, dx_research_code, diagnosis_date, update_date, status, coding_systemid
    ) VALUES (
        '$PATIENT_ID', '493', CURDATE(), CURDATE(), 'A', 'icd9'
    );"
fi

# ============================================================
# 3. Launch Firefox
# ============================================================
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="