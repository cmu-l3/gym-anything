#!/bin/bash
echo "=== Exporting unblock_data_entry_workflow result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Rule is disabled
RULE_ACTIVE=$(oc_query "SELECT COUNT(*) FROM rule_set_rule rsr JOIN rule r ON rsr.rule_id = r.rule_id WHERE r.name = 'SYS_BP_MAX_160' AND rsr.status_id = 1")
RULE_DISABLED="false"
if [ "$RULE_ACTIVE" = "0" ]; then
    RULE_DISABLED="true"
fi
echo "Rule disabled: $RULE_DISABLED"

# 2. Extract DM-105 data
DM105_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' LIMIT 1")

SYSTOLIC_SAVED="false"
DIASTOLIC_SAVED="false"
CRF_COMPLETED="false"
ACTUAL_SYSTOLIC=""
ACTUAL_DIASTOLIC=""

if [ -n "$DM105_SS_ID" ]; then
    # Look for value '165' associated with DM-105's CRFs
    SYS_VAL=$(oc_query "SELECT value FROM item_data idt JOIN event_crf ec ON idt.event_crf_id = ec.event_crf_id WHERE ec.study_subject_id = $DM105_SS_ID AND value = '165' LIMIT 1")
    if [ -n "$SYS_VAL" ]; then
        SYSTOLIC_SAVED="true"
        ACTUAL_SYSTOLIC="165"
    else
        # Find whatever they actually saved to report back
        ACTUAL_SYSTOLIC=$(oc_query "SELECT value FROM item_data idt JOIN event_crf ec ON idt.event_crf_id = ec.event_crf_id JOIN item i ON idt.item_id = i.item_id WHERE ec.study_subject_id = $DM105_SS_ID AND (LOWER(i.name) LIKE '%sys%' OR value ~ '^[1-9][0-9]{2}$') LIMIT 1")
    fi

    # Look for value '95'
    DIA_VAL=$(oc_query "SELECT value FROM item_data idt JOIN event_crf ec ON idt.event_crf_id = ec.event_crf_id WHERE ec.study_subject_id = $DM105_SS_ID AND value = '95' LIMIT 1")
    if [ -n "$DIA_VAL" ]; then
        DIASTOLIC_SAVED="true"
        ACTUAL_DIASTOLIC="95"
    else
        ACTUAL_DIASTOLIC=$(oc_query "SELECT value FROM item_data idt JOIN event_crf ec ON idt.event_crf_id = ec.event_crf_id JOIN item i ON idt.item_id = i.item_id WHERE ec.study_subject_id = $DM105_SS_ID AND (LOWER(i.name) LIKE '%dia%' OR value ~ '^[1-9][0-9]$') LIMIT 1")
    fi

    # Check if ANY CRF for DM-105 is marked complete (status_id = 2)
    COMPLETED=$(oc_query "SELECT status_id FROM event_crf WHERE study_subject_id = $DM105_SS_ID AND status_id = 2 LIMIT 1")
    if [ -n "$COMPLETED" ]; then
        CRF_COMPLETED="true"
    fi
fi

echo "Systolic saved: $SYSTOLIC_SAVED (Found: $ACTUAL_SYSTOLIC)"
echo "Diastolic saved: $DIASTOLIC_SAVED (Found: $ACTUAL_DIASTOLIC)"
echo "CRF completed: $CRF_COMPLETED"

# 3. Check audit log for anti-gaming
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
echo "Audit count: $AUDIT_LOG_COUNT (baseline: $AUDIT_BASELINE_COUNT)"

# Write JSON result
TEMP_JSON=$(mktemp /tmp/unblock_workflow_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rule_disabled": $RULE_DISABLED,
    "systolic_saved": $SYSTOLIC_SAVED,
    "diastolic_saved": $DIASTOLIC_SAVED,
    "crf_completed": $CRF_COMPLETED,
    "actual_systolic": "$(json_escape "${ACTUAL_SYSTOLIC:-}")",
    "actual_diastolic": "$(json_escape "${ACTUAL_DIASTOLIC:-}")",
    "audit_baseline": ${AUDIT_BASELINE_COUNT:-0},
    "audit_current": ${AUDIT_LOG_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null)"
}
EOF

# Move securely
rm -f /tmp/unblock_workflow_result.json 2>/dev/null || sudo rm -f /tmp/unblock_workflow_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/unblock_workflow_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/unblock_workflow_result.json
chmod 666 /tmp/unblock_workflow_result.json 2>/dev/null || sudo chmod 666 /tmp/unblock_workflow_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written."
cat /tmp/unblock_workflow_result.json
echo "=== Export Complete ==="