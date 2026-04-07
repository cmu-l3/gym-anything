#!/bin/bash
echo "=== Setting up admin_recovery task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_timestamp

# --- 1. Get Study IDs ---
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' LIMIT 1")

if [ -z "$DM_STUDY_ID" ] || [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: Required studies not found in database"
    exit 1
fi

echo "DM Trial study_id: $DM_STUDY_ID"
echo "CV Registry study_id: $CV_STUDY_ID"

# Save study IDs for export script
echo "$DM_STUDY_ID" > /tmp/dm_study_id
echo "$CV_STUDY_ID" > /tmp/cv_study_id

# --- 2. Ensure mrivera exists and lock the account ---
MRIVERA_EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'mrivera'" 2>/dev/null || echo "0")
if [ "${MRIVERA_EXISTS:-0}" = "0" ]; then
    echo "Creating mrivera user account..."
    oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created)
              VALUES ('mrivera', 'da39a3ee5e6b4b0d3255bfef95601890afd80709', 'Michael', 'Rivera', 'mrivera@clinical.org', 1, 1, NOW())" 2>/dev/null || true
fi

echo "Locking mrivera's account..."
oc_query "UPDATE user_account SET account_non_locked = false, status_id = 1 WHERE user_name = 'mrivera'" 2>/dev/null || true

# --- 3. Remove subjects DM-101 and DM-103 ---
for SUBJ in "DM-101" "DM-103"; do
    SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$SUBJ' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$SS_ID" ]; then
        echo "Removing subject $SUBJ (status_id = 5)..."
        # Set study_subject to removed
        oc_query "UPDATE study_subject SET status_id = 5 WHERE study_subject_id = $SS_ID" 2>/dev/null || true
        # Also set the underlying subject demographic record to removed
        SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $SS_ID LIMIT 1")
        if [ -n "$SUBJ_ID" ]; then
            oc_query "UPDATE subject SET status_id = 5 WHERE subject_id = $SUBJ_ID" 2>/dev/null || true
        fi
    else
        echo "WARNING: Subject $SUBJ not found, creating..."
        # Minimal subject creation if missing (unlikely given standard env, but safe fallback)
        oc_query "INSERT INTO subject (date_of_birth, gender, status_id, owner_id, date_created) VALUES ('1970-01-01', 'm', 5, 1, NOW())" 2>/dev/null || true
        NEW_SUBJ_ID=$(oc_query "SELECT subject_id FROM subject ORDER BY subject_id DESC LIMIT 1")
        oc_query "INSERT INTO study_subject (label, subject_id, study_id, status_id, owner_id, date_created) VALUES ('$SUBJ', $NEW_SUBJ_ID, $DM_STUDY_ID, 5, 1, NOW())" 2>/dev/null || true
    fi
done

# --- 4. Remove mrivera's role in CV-REG-2023 ---
echo "Removing mrivera's CV Registry role..."
oc_query "DELETE FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $CV_STUDY_ID" 2>/dev/null || true

# --- 5. Record baselines ---
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

NONCE=$(generate_result_nonce)
echo "Nonce: $NONCE"

# --- 6. Open UI ---
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
switch_active_study "DM-TRIAL-2024"
focus_firefox
sleep 1

take_screenshot /tmp/task_start_screenshot.png

echo "=== admin_recovery setup complete ==="