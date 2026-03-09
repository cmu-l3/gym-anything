#!/bin/bash
set -e
echo "=== Setting up task: add_ongoing_concerns ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure OSCAR is running
# ============================================================
wait_for_oscar_http 120

# ============================================================
# 2. Ensure patient Maria Santos exists
# ============================================================
echo "Ensuring patient Maria Santos exists..."

MARIA_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Maria' AND last_name='Santos'" 2>/dev/null || echo "0")

if [ "${MARIA_EXISTS:-0}" -lt 1 ]; then
    echo "Creating patient Maria Santos..."
    
    # Get next available demographic_no
    NEXT_DEMO=$(oscar_query "SELECT COALESCE(MAX(demographic_no),0)+1 FROM demographic" 2>/dev/null || echo "100")
    
    # Insert demographic record
    oscar_query "INSERT INTO demographic (
        demographic_no, first_name, last_name, sex, date_of_birth, 
        hin, ver, address, city, province, postal, phone,
        patient_status, date_joined, chart_no, roster_status,
        family_doctor, provider_no, year_of_birth, month_of_birth
    ) VALUES (
        ${NEXT_DEMO}, 'Maria', 'Santos', 'F', '1962-08-14',
        '6847291053', 'AB', '247 Bloor Street West', 'Toronto', 'ON', 'M5S1V6', '416-555-0187',
        'AC', CURDATE(), '${NEXT_DEMO}', 'RO',
        '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>', '999998', '1962', '08'
    );" 2>/dev/null || true

    # Add admission record required for some views
    oscar_query "INSERT IGNORE INTO admission (
        client_id, admission_date, program_id, provider_no, admission_status, team_id
    ) VALUES (
        ${NEXT_DEMO}, NOW(), 10016, '999998', 'current', 0
    );" 2>/dev/null || true

    echo "Patient Maria Santos created with demographic_no=${NEXT_DEMO}"
else
    echo "Patient Maria Santos already exists"
fi

# Get Maria's demographic_no for verification and setup
MARIA_DEMO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1" 2>/dev/null)
echo "${MARIA_DEMO}" > /tmp/maria_demo_no.txt
echo "Maria Santos demographic_no: ${MARIA_DEMO}"

# ============================================================
# 3. Clear ANY existing ongoing concerns for this patient
#    We want a clean state for the agent to add the specific 3.
# ============================================================
echo "Clearing existing ongoing concerns for Maria Santos..."
# Delete links in casemgmt_issue for this patient
oscar_query "DELETE FROM casemgmt_issue WHERE demographic_no='${MARIA_DEMO}'" 2>/dev/null || true
echo "Cleared previous issues."

# ============================================================
# 4. Record initial state (should be 0 after clear, but good practice)
# ============================================================
INITIAL_ISSUE_COUNT=$(oscar_query "SELECT COUNT(*) FROM casemgmt_issue WHERE demographic_no='${MARIA_DEMO}'" 2>/dev/null || echo "0")
echo "${INITIAL_ISSUE_COUNT}" > /tmp/initial_issue_count.txt
echo "Initial issue count: ${INITIAL_ISSUE_COUNT}"

# ============================================================
# 5. Launch Firefox on OSCAR login page
# ============================================================
ensure_firefox_on_oscar

# ============================================================
# 6. Take initial screenshot
# ============================================================
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="