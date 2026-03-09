#!/bin/bash
# Setup script for Record Immunization task
set -e

echo "=== Setting up Record Immunization Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Oscar to be ready
wait_for_oscar_http 120

# 2. Ensure patient Lucas Tremblay exists (Pediatric case)
#    We check by name. If not found, we insert him.
echo "Checking for patient Lucas Tremblay..."
PATIENT_ID=$(get_patient_id "Lucas" "Tremblay")

if [ -z "$PATIENT_ID" ]; then
    echo "Creating patient Lucas Tremblay..."
    # DOB 2024-03-15 (approx 1 year old relative to task context)
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth,
        address, city, province, postal, phone, patient_status,
        date_joined, chart_no, provider_no, roster_status, year_of_birth, month_of_birth
    ) VALUES (
        'Tremblay', 'Lucas', 'M', '2024-03-15',
        '882 Maple Ave', 'Toronto', 'ON', 'M4B 1B3',
        '416-555-0199', 'AC',
        CURDATE(), '20250215', '999998', 'RO', '2024', '03'
    );"
    PATIENT_ID=$(get_patient_id "Lucas" "Tremblay")
    echo "Created patient with ID: $PATIENT_ID"
else
    echo "Patient exists with ID: $PATIENT_ID"
fi

# 3. Clean up any existing immunizations for this patient on "today" 
#    to ensure the agent actually does the work and we don't pick up stale data.
#    We delete any MMR or Meningococcal records for this patient.
echo "Cleaning up previous immunization records for this patient..."
if [ -n "$PATIENT_ID" ]; then
    oscar_query "DELETE FROM immunizations WHERE demographic_no='$PATIENT_ID' AND (immunization_name LIKE '%MMR%' OR immunization_name LIKE '%Measles%' OR immunization_name LIKE '%Men%' OR immunization_name LIKE '%Mening%');"
fi

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "$PATIENT_ID" > /tmp/task_patient_id.txt

# 5. Open Firefox on Oscar login page
ensure_firefox_on_oscar

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="