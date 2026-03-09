#!/bin/bash
echo "=== Setting up crf_assignment_and_entry task ==="

source /workspace/scripts/task_utils.sh

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial not found in database"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

# ---------------------------------------------------------------
# Add event definitions if they don't exist
# ---------------------------------------------------------------

BASELINE_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Baseline Assessment' AND status_id != 3")
if [ "$BASELINE_EXISTS" = "0" ] || [ -z "$BASELINE_EXISTS" ]; then
    echo "Adding Baseline Assessment event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Baseline Assessment', 'Initial baseline study visit', false, 'Scheduled', 1, 1, NOW(), 'SE_DM_BASELINE', 1)"
    echo "Baseline Assessment event definition added"
else
    echo "Baseline Assessment event definition already exists"
fi

FOLLOWUP_EXISTS=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND name = 'Follow-up Visit' AND status_id != 3")
if [ "$FOLLOWUP_EXISTS" = "0" ] || [ -z "$FOLLOWUP_EXISTS" ]; then
    echo "Adding Follow-up Visit event definition to DM Trial..."
    oc_query "INSERT INTO study_event_definition (study_id, name, description, repeating, type, status_id, owner_id, date_created, oc_oid, ordinal) VALUES ($DM_STUDY_ID, 'Follow-up Visit', 'Follow-up visit for safety and efficacy assessment', true, 'Scheduled', 1, 1, NOW(), 'SE_DM_FOLLOWUP', 2)"
    echo "Follow-up Visit event definition added"
else
    echo "Follow-up Visit event definition already exists"
fi

# ---------------------------------------------------------------
# Clean up any existing Vital Signs CRF records (cascade order)
# ---------------------------------------------------------------
echo "Checking for existing Vital Signs CRF..."
EXISTING_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE LOWER(TRIM(name)) = 'vital signs' LIMIT 1")

if [ -n "$EXISTING_CRF_ID" ]; then
    echo "Found existing Vital Signs CRF (id=$EXISTING_CRF_ID). Removing for clean state..."

    # 1. Delete item_data referencing event_crfs that use any version of this CRF
    oc_query "DELETE FROM item_data WHERE event_crf_id IN (
        SELECT ec.event_crf_id FROM event_crf ec
        JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id
        WHERE cv.crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true
    echo "  Deleted item_data rows"

    # 2. Delete event_crf rows using any version of this CRF
    oc_query "DELETE FROM event_crf WHERE crf_version_id IN (
        SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true
    echo "  Deleted event_crf rows"

    # 3. Delete event_definition_crf rows for this CRF (direct crf_id reference)
    oc_query "DELETE FROM event_definition_crf WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    echo "  Deleted event_definition_crf rows (crf_id)"

    # 4. Also delete event_definition_crf rows via crf_version join
    oc_query "DELETE FROM event_definition_crf WHERE crf_version_id IN (
        SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true
    echo "  Deleted event_definition_crf rows (via crf_version)"

    # 5. Delete item_form_metadata for all versions of this CRF
    oc_query "DELETE FROM item_form_metadata WHERE crf_version_id IN (
        SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true
    echo "  Deleted item_form_metadata rows"

    # 6. Delete the crf_version rows
    oc_query "DELETE FROM crf_version WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    echo "  Deleted crf_version rows"

    # 7. Finally delete the crf record itself
    oc_query "DELETE FROM crf WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    echo "  Deleted crf record"

    echo "Vital Signs CRF cleanup complete"
else
    echo "No existing Vital Signs CRF found. Clean state confirmed."
fi

# ---------------------------------------------------------------
# Copy the CRF template file to the user's home directory
# ---------------------------------------------------------------
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/vital_signs_crf.xls
    chown ga:ga /home/ga/vital_signs_crf.xls
    chmod 644 /home/ga/vital_signs_crf.xls
    echo "CRF template copied to /home/ga/vital_signs_crf.xls"
else
    echo "WARNING: CRF template not found at /workspace/data/sample_crf.xls"
fi

# ---------------------------------------------------------------
# Record baseline counts for verification
# ---------------------------------------------------------------
INITIAL_CRF_COUNT=$(oc_query "SELECT COUNT(*) FROM crf WHERE status_id != 3")
echo "${INITIAL_CRF_COUNT:-0}" > /tmp/initial_crf_count
echo "Initial CRF count: ${INITIAL_CRF_COUNT:-0}"

INITIAL_EDC_COUNT=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc JOIN study_event_definition sed ON edc.study_event_definition_id = sed.study_event_definition_id WHERE sed.study_id = $DM_STUDY_ID AND edc.status_id != 3")
echo "${INITIAL_EDC_COUNT:-0}" > /tmp/initial_edc_count
echo "Initial event_definition_crf count for DM Trial: ${INITIAL_EDC_COUNT:-0}"

# Verify pre-existing subject DM-102 exists
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
if [ -z "$DM102_SS_ID" ]; then
    echo "WARNING: Subject DM-102 not found in DM Trial"
else
    echo "Confirmed: Subject DM-102 exists (study_subject_id=$DM102_SS_ID)"
fi

# Clean any pre-existing events for DM-102 to ensure a clean state for event scheduling
if [ -n "$DM102_SS_ID" ]; then
    # Remove item_data and event_crf data first
    oc_query "DELETE FROM item_data WHERE event_crf_id IN (
        SELECT event_crf_id FROM event_crf WHERE study_subject_id = $DM102_SS_ID
    )" 2>/dev/null || true
    oc_query "DELETE FROM event_crf WHERE study_subject_id = $DM102_SS_ID" 2>/dev/null || true
    oc_query "DELETE FROM study_event WHERE study_subject_id = $DM102_SS_ID" 2>/dev/null || true
    echo "Cleared pre-existing events for DM-102"
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded"

# ---------------------------------------------------------------
# Ensure Firefox is running and logged in
# ---------------------------------------------------------------
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30

# Verify login state - handles 404, login page, password reset
ensure_logged_in

# Switch the active study to Phase II Diabetes Trial in the browser
switch_active_study "DM-TRIAL-2024"

focus_firefox
sleep 1

DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 0.5
focus_firefox

# ---------------------------------------------------------------
# Record audit log baseline AFTER all setup navigation
# ---------------------------------------------------------------
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

# Generate integrity nonce to detect result file tampering
NONCE=$(generate_result_nonce)
echo "Result integrity nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== crf_assignment_and_entry task setup complete ==="
