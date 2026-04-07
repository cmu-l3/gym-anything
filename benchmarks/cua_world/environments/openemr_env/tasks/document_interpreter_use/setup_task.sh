#!/bin/bash
# Setup script for Document Interpreter Use Task

echo "=== Setting up Document Interpreter Use Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Task configuration
PATIENT_PID=5
PATIENT_FNAME="Maria"
PATIENT_LNAME="Santos"
PATIENT_DOB="1958-09-12"
PATIENT_LANGUAGE="Spanish"
VISIT_REASON="Follow-up for Diabetes Type 2"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Ensure patient Maria Santos exists with Spanish as primary language
echo "Setting up patient Maria Santos..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
INSERT INTO patient_data (pid, fname, lname, DOB, sex, language, street, city, state, postal_code, phone_cell)
VALUES ($PATIENT_PID, '$PATIENT_FNAME', '$PATIENT_LNAME', '$PATIENT_DOB', 'Female', '$PATIENT_LANGUAGE', '2847 Oak Avenue', 'Springfield', 'MA', '01103', '555-0198')
ON DUPLICATE KEY UPDATE 
    fname='$PATIENT_FNAME', 
    lname='$PATIENT_LNAME', 
    DOB='$PATIENT_DOB',
    language='$PATIENT_LANGUAGE',
    sex='Female';
" 2>/dev/null

# Verify patient was created/updated
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname, language FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Failed to create patient!"
    exit 1
fi
echo "Patient verified: $PATIENT_CHECK"

# Add diabetes to problem list if not exists
echo "Setting up diabetes diagnosis..."
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
INSERT IGNORE INTO lists (pid, type, title, begdate, diagnosis, outcome, occurrence)
VALUES ($PATIENT_PID, 'medical_problem', 'Type 2 Diabetes Mellitus', '2015-03-20', 'ICD10:E11.9', 1, 1);
" 2>/dev/null

# Get the next encounter number
NEXT_ENCOUNTER=$(openemr_query "SELECT IFNULL(MAX(encounter), 0) + 1 FROM form_encounter" 2>/dev/null || echo "1")
echo "Creating encounter number: $NEXT_ENCOUNTER"

# Create today's encounter for the patient
TODAY=$(date +%Y-%m-%d)
echo "Creating encounter for today: $TODAY"
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e "
INSERT INTO form_encounter (date, reason, facility_id, pid, encounter, sensitivity, provider_id, onset_date)
SELECT '$TODAY', '$VISIT_REASON', 3, $PATIENT_PID, $NEXT_ENCOUNTER, 'normal', 1, '$TODAY'
WHERE NOT EXISTS (
    SELECT 1 FROM form_encounter WHERE pid=$PATIENT_PID AND date='$TODAY' AND reason='$VISIT_REASON'
);
" 2>/dev/null

# Get the actual encounter ID created
ENCOUNTER_ID=$(openemr_query "SELECT encounter FROM form_encounter WHERE pid=$PATIENT_PID AND date='$TODAY' ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "Encounter ID: $ENCOUNTER_ID"
echo "$ENCOUNTER_ID" > /tmp/task_encounter_id.txt

# Record initial clinical notes count for this patient
INITIAL_NOTES_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_clinical_notes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_NOTES_COUNT" > /tmp/initial_notes_count.txt
echo "Initial clinical notes count: $INITIAL_NOTES_COUNT"

# Record initial forms count for verification
INITIAL_FORMS_COUNT=$(openemr_query "SELECT COUNT(*) FROM forms WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_FORMS_COUNT" > /tmp/initial_forms_count.txt
echo "Initial forms count: $INITIAL_FORMS_COUNT"

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for audit
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo ""
echo "=== Document Interpreter Use Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  Patient: $PATIENT_FNAME $PATIENT_LNAME (PID: $PATIENT_PID)"
echo "  Primary Language: $PATIENT_LANGUAGE"
echo "  Today's Visit: $VISIT_REASON"
echo ""
echo "  Document the following interpreter service use:"
echo "    - Language: Spanish"
echo "    - Interpreter Type: Telephone/Phone"
echo "    - Service Provider: CyraCom Language Services"
echo "    - Interpreter ID: SP-44721"
echo "    - Duration: 25 minutes"
echo "    - Note: Telephone interpreter used for diabetes follow-up visit."
echo ""
echo "  Login credentials: admin / pass"
echo ""