#!/bin/bash
echo "=== Exporting setup_new_clinical_study result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# --- Fetch DB Baselines ---
BASELINE_MAX_STUDY_ID=$(cat /tmp/baseline_max_study_id 2>/dev/null || echo "0")

# --- Criterion 1: Check if the new study exists ---
STUDY_DATA=$(oc_query "SELECT study_id, name, principal_investigator, sponsor FROM study WHERE unique_identifier = 'PK-HV-001' AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")

STUDY_EXISTS="false"
STUDY_ID="0"
STUDY_NAME=""
STUDY_PI=""
STUDY_SPONSOR=""

if [ -n "$STUDY_DATA" ]; then
    STUDY_EXISTS="true"
    STUDY_ID=$(echo "$STUDY_DATA" | cut -d'|' -f1)
    STUDY_NAME=$(echo "$STUDY_DATA" | cut -d'|' -f2)
    STUDY_PI=$(echo "$STUDY_DATA" | cut -d'|' -f3)
    STUDY_SPONSOR=$(echo "$STUDY_DATA" | cut -d'|' -f4)
    echo "Study Found: id=$STUDY_ID, name='$STUDY_NAME', pi='$STUDY_PI', sponsor='$STUDY_SPONSOR'"
else
    echo "Study 'PK-HV-001' not found in database."
fi

# --- Criterion 2 & 3: Check Event Definitions ---
EVENT1_EXISTS="false"
EVENT1_TYPE=""
EVENT1_REPEATING=""

EVENT2_EXISTS="false"
EVENT2_TYPE=""
EVENT2_REPEATING=""

if [ "$STUDY_EXISTS" = "true" ]; then
    EVENT1_DATA=$(oc_query "SELECT type, repeating::text FROM study_event_definition WHERE study_id = $STUDY_ID AND LOWER(name) LIKE '%dosing visit%' AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$EVENT1_DATA" ]; then
        EVENT1_EXISTS="true"
        EVENT1_TYPE=$(echo "$EVENT1_DATA" | cut -d'|' -f1)
        EVENT1_REPEATING=$(echo "$EVENT1_DATA" | cut -d'|' -f2)
    fi

    EVENT2_DATA=$(oc_query "SELECT type, repeating::text FROM study_event_definition WHERE study_id = $STUDY_ID AND LOWER(name) LIKE '%safety follow-up%' AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$EVENT2_DATA" ]; then
        EVENT2_EXISTS="true"
        EVENT2_TYPE=$(echo "$EVENT2_DATA" | cut -d'|' -f1)
        EVENT2_REPEATING=$(echo "$EVENT2_DATA" | cut -d'|' -f2)
    fi
fi

echo "Event 1 (Dosing): exists=$EVENT1_EXISTS, type=$EVENT1_TYPE, repeating=$EVENT1_REPEATING"
echo "Event 2 (Safety): exists=$EVENT2_EXISTS, type=$EVENT2_TYPE, repeating=$EVENT2_REPEATING"

# --- Criterion 4: Check User Role Assignment ---
ROLE_EXISTS="false"
ROLE_NAME=""

if [ "$STUDY_EXISTS" = "true" ]; then
    ROLE_DATA=$(oc_query "SELECT role_name FROM study_user_role WHERE study_id = $STUDY_ID AND user_name = 'mrivera' AND status_id = 1 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$ROLE_DATA" ]; then
        ROLE_EXISTS="true"
        ROLE_NAME="$ROLE_DATA"
    fi
fi
echo "User mrivera role: exists=$ROLE_EXISTS, role_name='$ROLE_NAME'"

# --- Audit Log Check ---
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# --- Write Results to JSON ---
TEMP_JSON=$(mktemp /tmp/setup_study_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "baseline_max_study_id": $BASELINE_MAX_STUDY_ID,
    "study_exists": $STUDY_EXISTS,
    "study_id": $STUDY_ID,
    "study_name": "$(json_escape "${STUDY_NAME:-}")",
    "study_pi": "$(json_escape "${STUDY_PI:-}")",
    "study_sponsor": "$(json_escape "${STUDY_SPONSOR:-}")",
    "event1_exists": $EVENT1_EXISTS,
    "event1_type": "$(json_escape "${EVENT1_TYPE:-}")",
    "event1_repeating": "$(json_escape "${EVENT1_REPEATING:-}")",
    "event2_exists": $EVENT2_EXISTS,
    "event2_type": "$(json_escape "${EVENT2_TYPE:-}")",
    "event2_repeating": "$(json_escape "${EVENT2_REPEATING:-}")",
    "role_exists": $ROLE_EXISTS,
    "role_name": "$(json_escape "${ROLE_NAME:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")"
}
EOF

# Safe move
rm -f /tmp/setup_study_result.json 2>/dev/null || sudo rm -f /tmp/setup_study_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/setup_study_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/setup_study_result.json
chmod 666 /tmp/setup_study_result.json 2>/dev/null || sudo chmod 666 /tmp/setup_study_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON exported to /tmp/setup_study_result.json"
cat /tmp/setup_study_result.json

echo "=== Export complete ==="