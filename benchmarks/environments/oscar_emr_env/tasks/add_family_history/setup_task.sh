#!/bin/bash
set -e
echo "=== Setting up Add Family History task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure OSCAR is running and accessible
# ============================================================
wait_for_oscar_http 300

# ============================================================
# 2. Create patient Emily Watson if not already present
# ============================================================
echo "Creating patient Emily Watson..."

# Check if patient already exists
EXISTING=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE demographic_no=80701" 2>/dev/null || echo "0")

if [ "${EXISTING:-0}" -lt 1 ]; then
    oscar_query "
    INSERT INTO demographic (
        demographic_no, last_name, first_name, sex, date_of_birth,
        year_of_birth, month_of_birth, date_of_birth_day,
        hin, ver, province, address, city, postal, phone,
        patient_status, roster_status, provider_no, family_doctor
    ) VALUES (
        80701, 'Watson', 'Emily', 'F', '1978-06-22',
        '1978', '06', '22',
        '9283746501', 'AB', 'ON', '45 Maple Drive', 'Ottawa', 'K1A 0B1', '613-555-0192',
        'AC', 'RO', '999998', '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>'
    );" 2>/dev/null || echo "Patient creation query failed"

    # Add admission record to make patient 'current'
    oscar_query "
    INSERT IGNORE INTO admission (
        client_id, admission_date, admission_status, provider_no, program_id
    ) VALUES (
        80701, NOW(), 'current', '999998', 
        (SELECT program_id FROM program WHERE name='OSCAR' LIMIT 1)
    );" 2>/dev/null || true
    
    echo "Patient Emily Watson created (demographic_no: 80701)"
else
    echo "Patient Emily Watson already exists"
fi

# ============================================================
# 3. Clear any pre-existing family history for this patient
#    (CRITICAL: Ensures agent actually does the work)
# ============================================================
echo "Clearing any existing family history data..."

# Clear CPP family history field
oscar_query "UPDATE casemgmt_cpp SET familyHistory='' WHERE demographic_no='80701'" 2>/dev/null || true

# Remove any family history notes (linked via issues)
# This removes notes associated with 'FamHistory' issue type
oscar_query "
DELETE cn FROM casemgmt_note cn
INNER JOIN casemgmt_issue ci ON cn.note_id = ci.note_id
INNER JOIN issue i ON ci.issue_id = i.issue_id
WHERE cn.demographic_no = '80701'
AND (i.type = 'FamHistory' OR i.code LIKE '%FamHx%');" 2>/dev/null || true

# Clear from temporary save table if present
oscar_query "DELETE FROM CaseManagementTmpSave WHERE demographicNo='80701'" 2>/dev/null || true

echo "Family history cleared for patient 80701"

# ============================================================
# 4. Launch Firefox on OSCAR login page
# ============================================================
echo "Launching Firefox..."
ensure_firefox_on_oscar

# ============================================================
# 5. Take initial screenshot
# ============================================================
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="