#!/bin/bash
set -e
echo "=== Setting up write_consultation_request task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure patient Maria Santos exists (demographic_no=10001)
# ============================================================
echo "Setting up patient Maria Santos..."
# Clean up if exists to ensure clean slate (optional, but good for idempotency)
# We use INSERT IGNORE to keep it if it exists, but ensure it has correct ID
oscar_query "INSERT IGNORE INTO demographic
    (demographic_no, last_name, first_name, sex, date_of_birth, patient_status,
     hin, ver, province, city, address, postal, phone, year_of_birth, month_of_birth, date_of_birth_day)
    VALUES (10001, 'Santos', 'Maria', 'F', '1958-06-22', 'AC',
     '9876543217', 'AB', 'ON', 'Toronto', '45 Queen St W', 'M5H2M5', '416-555-0198',
     '1958', '06', '22');"

# Ensure linked in demographic_merged for chart access
oscar_query "INSERT IGNORE INTO demographic_merged (demographic_no, merged_to)
    VALUES (10001, 10001);" 2>/dev/null || true

# Add admission record so patient appears in search
oscar_query "INSERT IGNORE INTO admission
    (client_id, admission_date, discharge_date, program_id, provider_no, admission_status, team_id)
    VALUES (10001, NOW(), NULL, 0, '999998', 'current', 0);" 2>/dev/null || true

echo "Patient Maria Santos confirmed (demographic_no=10001)."

# ============================================================
# 2. Set up Cardiology consultation service
# ============================================================
echo "Setting up Cardiology consultation service..."
oscar_query "INSERT IGNORE INTO consultationServices (serviceId, serviceDesc, active)
    VALUES (1, 'Cardiology', 1);"

# ============================================================
# 3. Set up specialist Dr. Robert Hartfield
# ============================================================
echo "Setting up specialist Dr. Robert Hartfield..."
oscar_query "INSERT IGNORE INTO professionalSpecialists
    (specId, fName, lName, proLetters, address, phone, fax, specType, annotation, referralNo, eDataUrl, eDataOscarKey, eDataServiceKey, eDataServiceName)
    VALUES (1, 'Robert', 'Hartfield', 'MD FRCPC',
     '200 Elizabeth St, Toronto, ON M5G 2C4', '416-555-0300', '416-555-0301',
     'Cardiology', 'Toronto General Hospital - Cardiology Division', '', '', '', '', '');"

# Link specialist to consultation service
oscar_query "INSERT IGNORE INTO consultationServiceSpecialists (serviceId, specId)
    VALUES (1, 1);" 2>/dev/null || true

echo "Specialist Dr. Robert Hartfield linked to Cardiology service."

# ============================================================
# 4. Record initial state
# ============================================================
# Count existing consultation requests
INITIAL_CONSULT_COUNT=$(oscar_query "SELECT COUNT(*) FROM consultationRequests" 2>/dev/null || echo "0")
echo "$INITIAL_CONSULT_COUNT" > /tmp/initial_consult_count.txt

# Store IDs of existing requests to identify the new one later
oscar_query "SELECT id FROM consultationRequests ORDER BY id" 2>/dev/null > /tmp/initial_consult_ids.txt || touch /tmp/initial_consult_ids.txt

# ============================================================
# 5. Start Firefox on OSCAR login page
# ============================================================
echo "Starting Firefox..."
ensure_firefox_on_oscar

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="