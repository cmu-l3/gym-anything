#!/bin/bash
echo "=== Setting up medical_coding_query_resolution task ==="

source /workspace/scripts/task_utils.sh

# Get CV Registry study_id
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1" 2>/dev/null)
if [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: Cardiovascular Outcomes Registry not found"
    exit 1
fi
echo "CV Registry study_id: $CV_STUDY_ID"

# 1. Create subjects if they don't exist
for i in 1 2 3; do
    LABEL="CV-10${i}"
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$LABEL' AND study_id = $CV_STUDY_ID LIMIT 1" 2>/dev/null)
    if [ -z "$SS_ID" ]; then
        echo "Creating subject $LABEL..."
        oc_query "INSERT INTO subject (date_of_birth, gender, date_created, owner_id, status_id) VALUES ('1960-01-01', 'm', NOW(), 1, 1)" 2>/dev/null || true
        SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1" 2>/dev/null)
        if [ -n "$SUBJ_ID" ]; then
            oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, enrollment_date, date_created, owner_id) VALUES ('$LABEL', $SUBJ_ID, $CV_STUDY_ID, 1, NOW(), NOW(), 1)" 2>/dev/null || true
            SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$LABEL' AND study_id = $CV_STUDY_ID LIMIT 1" 2>/dev/null)
        fi
    fi
    # Store ID dynamically
    eval "CV10${i}_SS_ID=$SS_ID"
done

# 2. Create the CSV Dictionary
echo "Creating MedDRA extract CSV..."
cat << 'EOF' > /home/ga/meddra_extract.csv
Verbatim Term,Preferred Term,MedDRA LLT Code,System Organ Class
Severe Nausea,Nausea,10028813,Gastrointestinal disorders
Persistent Headache,Headache,10019211,Nervous system disorders
Mild Dizziness,Dizziness,10013573,Nervous system disorders
Fatigue,Fatigue,10016256,General disorders
Fever,Pyrexia,10037660,General disorders
EOF
chown ga:ga /home/ga/meddra_extract.csv
chmod 644 /home/ga/meddra_extract.csv

# 3. Create Discrepancy Notes
DN1_DESC="AE reported: Patient complained of severe nausea. Please provide MedDRA LLT code. [TASK_AE_1]"
DN2_DESC="AE reported: Persistent headache for 2 days. Please provide MedDRA LLT code. [TASK_AE_2]"
DN3_DESC="AE reported: Mild dizziness upon standing. Please provide MedDRA LLT code. [TASK_AE_3]"

# Clean up existing notes with these signatures to ensure clean state
echo "Cleaning up any existing task notes..."
oc_query "DELETE FROM dn_study_subject_map WHERE discrepancy_note_id IN (SELECT discrepancy_note_id FROM discrepancy_note WHERE description LIKE '%[TASK_AE_%')" 2>/dev/null || true
oc_query "DELETE FROM discrepancy_note WHERE description LIKE '%[TASK_AE_%'" 2>/dev/null || true

# Helper to create notes
create_dn() {
    local DESC="$1"
    local SS_ID="$2"
    if [ -z "$SS_ID" ]; then
        echo "WARNING: Missing SS_ID, skipping note: $DESC"
        return
    fi
    
    # 3 = Query type, 1 = New status
    oc_query "INSERT INTO discrepancy_note (description, discrepancy_note_type_id, resolution_status_id, detailed_notes, date_created, owner_id, entity_type, study_id) VALUES ('$DESC', 3, 1, '$DESC', NOW(), 1, 'studySubject', $CV_STUDY_ID)" 2>/dev/null || true
    local DN_ID=$(oc_query "SELECT discrepancy_note_id FROM discrepancy_note WHERE description = '$DESC' LIMIT 1" 2>/dev/null)
    
    if [ -n "$DN_ID" ]; then
        oc_query "INSERT INTO dn_study_subject_map (study_subject_id, discrepancy_note_id, column_name) VALUES ($SS_ID, $DN_ID, 'label')" 2>/dev/null || true
        echo "Created Note ID: $DN_ID for Subject: $SS_ID"
    else
        echo "Failed to create Note: $DESC"
    fi
}

create_dn "$DN1_DESC" "$CV101_SS_ID"
create_dn "$DN2_DESC" "$CV102_SS_ID"
create_dn "$DN3_DESC" "$CV103_SS_ID"

# 4. Record baselines
date +%s > /tmp/task_start_time
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# 5. Setup Browser UI
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "CV-REG-2023"
focus_firefox
sleep 1

take_screenshot /tmp/task_start_screenshot.png

echo "=== setup_task complete ==="