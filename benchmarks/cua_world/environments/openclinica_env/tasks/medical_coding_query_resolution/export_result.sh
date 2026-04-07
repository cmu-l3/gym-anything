#!/bin/bash
echo "=== Exporting medical_coding_query_resolution result ==="

source /workspace/scripts/task_utils.sh

# Capture final UI state
take_screenshot /tmp/task_end_screenshot.png

CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1" 2>/dev/null)

DN1_DESC="AE reported: Patient complained of severe nausea. Please provide MedDRA LLT code. [TASK_AE_1]"
DN2_DESC="AE reported: Persistent headache for 2 days. Please provide MedDRA LLT code. [TASK_AE_2]"
DN3_DESC="AE reported: Mild dizziness upon standing. Please provide MedDRA LLT code. [TASK_AE_3]"

check_dn() {
    local DESC="$1"
    local EXPECTED_CODE="$2"
    
    local PARENT_ID=$(oc_query "SELECT discrepancy_note_id FROM discrepancy_note WHERE description = '$DESC' LIMIT 1" 2>/dev/null)
    if [ -z "$PARENT_ID" ]; then
        echo "false|0|none"
        return
    fi
    
    local PARENT_STATUS=$(oc_query "SELECT resolution_status_id FROM discrepancy_note WHERE discrepancy_note_id = $PARENT_ID LIMIT 1" 2>/dev/null)
    if [ -z "$PARENT_STATUS" ]; then PARENT_STATUS="0"; fi
    
    # Check if child responses contain the expected code in description or detailed_notes
    local HAS_CODE=$(oc_query "SELECT COUNT(*) FROM discrepancy_note WHERE parent_dn_id = $PARENT_ID AND (description LIKE '%$EXPECTED_CODE%' OR detailed_notes LIKE '%$EXPECTED_CODE%')" 2>/dev/null)
    
    local CODE_FOUND="false"
    if [ -n "$HAS_CODE" ] && [ "$HAS_CODE" != "0" ]; then
        CODE_FOUND="true"
    fi
    
    echo "$CODE_FOUND|$PARENT_STATUS|$PARENT_ID"
}

echo "Checking CV-101 (Nausea)..."
DN1_RESULT=$(check_dn "$DN1_DESC" "10028813")
DN1_F=$(echo "$DN1_RESULT" | cut -d'|' -f1)
DN1_S=$(echo "$DN1_RESULT" | cut -d'|' -f2)
DN1_P=$(echo "$DN1_RESULT" | cut -d'|' -f3)

echo "Checking CV-102 (Headache)..."
DN2_RESULT=$(check_dn "$DN2_DESC" "10019211")
DN2_F=$(echo "$DN2_RESULT" | cut -d'|' -f1)
DN2_S=$(echo "$DN2_RESULT" | cut -d'|' -f2)
DN2_P=$(echo "$DN2_RESULT" | cut -d'|' -f3)

echo "Checking CV-103 (Dizziness)..."
DN3_RESULT=$(check_dn "$DN3_DESC" "10013573")
DN3_F=$(echo "$DN3_RESULT" | cut -d'|' -f1)
DN3_S=$(echo "$DN3_RESULT" | cut -d'|' -f2)
DN3_P=$(echo "$DN3_RESULT" | cut -d'|' -f3)

AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

TEMP_JSON=$(mktemp /tmp/medical_coding_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cv101": {
        "code_found": $DN1_F,
        "status_id": $DN1_S,
        "parent_id": "$DN1_P"
    },
    "cv102": {
        "code_found": $DN2_F,
        "status_id": $DN2_S,
        "parent_id": "$DN2_P"
    },
    "cv103": {
        "code_found": $DN3_F,
        "status_id": $DN3_S,
        "parent_id": "$DN3_P"
    },
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')"
}
EOF

rm -f /tmp/medical_coding_result.json 2>/dev/null || sudo rm -f /tmp/medical_coding_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/medical_coding_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/medical_coding_result.json
chmod 666 /tmp/medical_coding_result.json 2>/dev/null || sudo chmod 666 /tmp/medical_coding_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/medical_coding_result.json"
echo "=== Export Complete ==="