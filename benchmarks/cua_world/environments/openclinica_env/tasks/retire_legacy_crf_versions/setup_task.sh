#!/bin/bash
echo "=== Setting up retire_legacy_crf_versions task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Helper to deep clean CRFs to avoid foreign key conflicts
cleanup_crf() {
    local CRF_NAME="$1"
    local CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = '$CRF_NAME' LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$CRF_ID" ]; then
        echo "Cleaning up pre-existing CRF: $CRF_NAME (id=$CRF_ID)"
        oc_query "DELETE FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_ID))" 2>/dev/null || true
        oc_query "DELETE FROM event_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_ID)" 2>/dev/null || true
        oc_query "DELETE FROM event_definition_crf WHERE crf_id = $CRF_ID" 2>/dev/null || true
        oc_query "DELETE FROM event_definition_crf WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_ID)" 2>/dev/null || true
        oc_query "DELETE FROM item_form_metadata WHERE crf_version_id IN (SELECT crf_version_id FROM crf_version WHERE crf_id = $CRF_ID)" 2>/dev/null || true
        oc_query "DELETE FROM crf_version WHERE crf_id = $CRF_ID" 2>/dev/null || true
        oc_query "DELETE FROM crf WHERE crf_id = $CRF_ID" 2>/dev/null || true
    fi
}

echo "Ensuring clean state for target CRFs..."
cleanup_crf 'Vital Signs'
cleanup_crf 'Physical Exam'

# Insert fresh Vital Signs CRF
echo "Seeding 'Vital Signs' CRF..."
oc_query "INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid, source_study_id) VALUES (1, 'Vital Signs', 'Vital Signs CRF for capturing standard metabolic and circulatory measurements.', 1, NOW(), 'F_VITALSIGNS_1', 1)" 2>/dev/null || true
VS_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Vital Signs' LIMIT 1")

if [ -n "$VS_CRF_ID" ]; then
    oc_query "INSERT INTO crf_version (crf_id, name, description, revision_notes, status_id, date_created, owner_id, oc_oid) VALUES ($VS_CRF_ID, 'v1.0', 'Legacy Vital Signs Form', 'Initial protocol release', 1, NOW(), 1, 'v_F_VITALSIGNS_1_V10')" 2>/dev/null || true
    oc_query "INSERT INTO crf_version (crf_id, name, description, revision_notes, status_id, date_created, owner_id, oc_oid) VALUES ($VS_CRF_ID, 'v2.0', 'Updated Vital Signs Form', 'Added oxygen saturation', 1, NOW(), 1, 'v_F_VITALSIGNS_1_V20')" 2>/dev/null || true
fi

# Insert fresh Physical Exam CRF
echo "Seeding 'Physical Exam' CRF..."
oc_query "INSERT INTO crf (status_id, name, description, owner_id, date_created, oc_oid, source_study_id) VALUES (1, 'Physical Exam', 'Comprehensive physical examination tracking.', 1, NOW(), 'F_PHYSICALEX_1', 1)" 2>/dev/null || true
PE_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name = 'Physical Exam' LIMIT 1")

if [ -n "$PE_CRF_ID" ]; then
    oc_query "INSERT INTO crf_version (crf_id, name, description, revision_notes, status_id, date_created, owner_id, oc_oid) VALUES ($PE_CRF_ID, 'v1.0', 'Legacy PE Form', 'Initial protocol release', 1, NOW(), 1, 'v_F_PHYSICALEX_1_V10')" 2>/dev/null || true
    oc_query "INSERT INTO crf_version (crf_id, name, description, revision_notes, status_id, date_created, owner_id, oc_oid) VALUES ($PE_CRF_ID, 'v2.0', 'Updated PE Form', 'Expanded neurological section', 1, NOW(), 1, 'v_F_PHYSICALEX_1_V20')" 2>/dev/null || true
fi

# Record audit log baseline
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

# Generate nonce for anti-tampering
NONCE=$(generate_result_nonce)
echo "Result Nonce: $NONCE"

# Ensure Firefox running and logged in
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
focus_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== retire_legacy_crf_versions setup complete ==="