#!/bin/bash
echo "=== Setting up correct_subject_demographics task ==="

source /workspace/scripts/task_utils.sh

# 1. Resolve DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# 2. Get subject IDs for DM-101, DM-102, DM-103
get_subject_id() {
    local label=$1
    local sid
    sid=$(oc_query "SELECT subject_id FROM study_subject WHERE label = '$label' AND study_id = $DM_STUDY_ID LIMIT 1")
    echo "$sid"
}

DM101_SUBJ_ID=$(get_subject_id "DM-101")
DM102_SUBJ_ID=$(get_subject_id "DM-102")
DM103_SUBJ_ID=$(get_subject_id "DM-103")

if [ -z "$DM101_SUBJ_ID" ] || [ -z "$DM102_SUBJ_ID" ] || [ -z "$DM103_SUBJ_ID" ]; then
    echo "ERROR: Could not find all required subjects (DM-101, DM-102, DM-103)"
    exit 1
fi

# 3. Apply INCORRECT baseline demographics (the starting state the agent must fix)
echo "Applying incorrect baseline demographics..."

# DM-101: Set to Female ('f') - should be Male
oc_query "UPDATE subject SET gender = 'f' WHERE subject_id = $DM101_SUBJ_ID" 2>/dev/null || true

# DM-102: Set DOB to 1952-11-07 - should be 1958-06-22
oc_query "UPDATE subject SET date_of_birth = '1952-11-07' WHERE subject_id = $DM102_SUBJ_ID" 2>/dev/null || true

# DM-103: Set to Male ('m') and DOB to 1980-07-14 - should be Female and 1975-12-03
oc_query "UPDATE subject SET gender = 'm', date_of_birth = '1980-07-14' WHERE subject_id = $DM103_SUBJ_ID" 2>/dev/null || true

# 4. Record baseline of *other* subjects (to check for unintended changes)
# We will just hash or count the demographics of subjects other than 101, 102, 103
OTHER_SUBJ_CHECKSUM=$(oc_query "SELECT COUNT(*) || '-' || SUM(ASCII(gender)) || '-' || SUM(EXTRACT(EPOCH FROM date_of_birth)) FROM subject s JOIN study_subject ss ON s.subject_id = ss.subject_id WHERE ss.study_id = $DM_STUDY_ID AND ss.label NOT IN ('DM-101', 'DM-102', 'DM-103')" 2>/dev/null)
echo "${OTHER_SUBJ_CHECKSUM:-0}" > /tmp/baseline_other_subj_checksum

# 5. Record Audit Log Baseline (Anti-gaming)
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline: ${AUDIT_BASELINE:-0}"

# 6. Generate Nonce
NONCE=$(generate_result_nonce)
echo "Result Nonce: $NONCE"

# 7. Start/Configure Firefox
date +%s > /tmp/task_start_timestamp

if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"

# Navigate to Subject Matrix to give agent a good starting point
focus_firefox
sleep 1
DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool type --delay 20 'http://localhost:8080/OpenClinica/ListStudySubjects' 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 4

take_screenshot /tmp/task_start_screenshot.png

echo "=== correct_subject_demographics setup complete ==="