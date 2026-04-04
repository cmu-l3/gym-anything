#!/bin/bash
# Setup script for Add Medical History task

echo "=== Setting up Add Medical History Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Oscar is ready
wait_for_oscar_http 300

# 1. Ensure Patient Maria Santos exists
echo "Ensuring patient Maria Santos exists..."
PATIENT_CHECK=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_CHECK" ]; then
    echo "Creating patient Maria Santos..."
    # Insert demographic record
    oscar_query "
    INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, year_of_birth, month_of_birth, 
        address, city, province, postal, phone, 
        patient_status, roster_status, provider_no, date_joined, eff_date, hc_type
    ) VALUES (
        'Santos', 'Maria', 'F', '1985-07-22', '1985', '07',
        '42 Elm Street', 'Toronto', 'ON', 'M5V 2B7', '416-555-0199',
        'AC', 'RO', '999998', CURDATE(), CURDATE(), 'ON'
    );" 2>/dev/null

    # Get the ID of the new patient
    PATIENT_CHECK=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1" 2>/dev/null)
    
    # Create admission record (needed for eChart access)
    if [ -n "$PATIENT_CHECK" ]; then
        oscar_query "INSERT IGNORE INTO admission (client_id, admission_date, admission_status, program_id, provider_no, team_id) VALUES (${PATIENT_CHECK}, NOW(), 'current', 10001, '999998', 0);" 2>/dev/null || true
    fi
fi

if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Failed to create/find patient Maria Santos"
    exit 1
fi

echo "Patient Maria Santos confirmed (ID: $PATIENT_CHECK)"
echo "$PATIENT_CHECK" > /tmp/task_patient_id.txt

# 2. Record initial Medical History count
# In Oscar, CPP entries are often stored in casemgmt_note linked to issues of type 'MedHistory'
INITIAL_COUNT=$(oscar_query "
    SELECT COUNT(*) FROM casemgmt_note cn
    JOIN casemgmt_issue_notes cin ON cn.note_id = cin.note_id
    JOIN casemgmt_issue ci ON cin.id = ci.issue_id
    WHERE cn.demographic_no = '$PATIENT_CHECK'
    AND ci.type = 'MedHistory'
    AND cn.note NOT LIKE '%[Archived]%'
" 2>/dev/null || echo "0")

# Fallback: also check raw notes that might match keywords (in case pre-existing)
INITIAL_KEYWORD_COUNT=$(oscar_query "
    SELECT COUNT(*) FROM casemgmt_note 
    WHERE demographic_no = '$PATIENT_CHECK' 
    AND (LOWER(note) LIKE '%cholecystectomy%' OR LOWER(note) LIKE '%pneumonia%')
" 2>/dev/null || echo "0")

echo "$INITIAL_COUNT" > /tmp/initial_pmh_count.txt
echo "$INITIAL_KEYWORD_COUNT" > /tmp/initial_keyword_count.txt

echo "Initial PMH count: $INITIAL_COUNT"
echo "Initial keyword match count: $INITIAL_KEYWORD_COUNT"

# 3. Ensure Firefox is open and ready
ensure_firefox_on_oscar

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="