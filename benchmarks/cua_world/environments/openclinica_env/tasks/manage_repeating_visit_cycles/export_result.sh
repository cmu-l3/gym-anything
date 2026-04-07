#!/bin/bash
echo "=== Exporting manage_repeating_visit_cycles result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Resolve Identifiers
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")

echo "DM Trial study_id: $DM_STUDY_ID"
echo "Week 4 Follow-up SED id: $WEEK4_SED_ID"
echo "DM-101 study_subject_id: $DM101_SS_ID"

# -----------------------------------------------------------------------------
# Check for occurrences (sample_ordinal)
# -----------------------------------------------------------------------------
CYCLE2_FOUND="false"
CYCLE2_DATE=""
CYCLE3_FOUND="false"
CYCLE3_DATE=""
TOTAL_OCCURRENCES=0

if [ -n "$DM101_SS_ID" ] && [ -n "$WEEK4_SED_ID" ]; then
    TOTAL_OCCURRENCES=$(oc_query "SELECT COUNT(*) FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID")
    
    # Extract Cycle 2 (sample_ordinal = 2)
    CYCLE2_DATA=$(oc_query "SELECT date_start FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID AND sample_ordinal = 2 LIMIT 1")
    if [ -n "$CYCLE2_DATA" ]; then
        CYCLE2_FOUND="true"
        CYCLE2_DATE=$(echo "$CYCLE2_DATA" | cut -d' ' -f1) # Strip time portion if returned
    fi
    
    # Extract Cycle 3 (sample_ordinal = 3)
    CYCLE3_DATA=$(oc_query "SELECT date_start FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $WEEK4_SED_ID AND sample_ordinal = 3 LIMIT 1")
    if [ -n "$CYCLE3_DATA" ]; then
        CYCLE3_FOUND="true"
        CYCLE3_DATE=$(echo "$CYCLE3_DATA" | cut -d' ' -f1) # Strip time portion if returned
    fi
fi

echo "Total occurrences for DM-101 'Week 4 Follow-up': $TOTAL_OCCURRENCES"
echo "Cycle 2 Found: $CYCLE2_FOUND (Date: $CYCLE2_DATE)"
echo "Cycle 3 Found: $CYCLE3_FOUND (Date: $CYCLE3_DATE)"

# -----------------------------------------------------------------------------
# Audit log check (Anti-gaming)
# -----------------------------------------------------------------------------
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
echo "Audit Log: Current=$AUDIT_LOG_COUNT, Baseline=$AUDIT_BASELINE_COUNT"

# -----------------------------------------------------------------------------
# Write JSON output
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/repeating_cycles_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "total_occurrences": ${TOTAL_OCCURRENCES:-0},
    "cycle2_found": $CYCLE2_FOUND,
    "cycle2_date": "$(json_escape "${CYCLE2_DATE:-}")",
    "cycle3_found": $CYCLE3_FOUND,
    "cycle3_date": "$(json_escape "${CYCLE3_DATE:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safe file replacement
rm -f /tmp/repeating_cycles_result.json 2>/dev/null || sudo rm -f /tmp/repeating_cycles_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/repeating_cycles_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/repeating_cycles_result.json
chmod 666 /tmp/repeating_cycles_result.json 2>/dev/null || sudo chmod 666 /tmp/repeating_cycles_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Exported Result JSON:"
cat /tmp/repeating_cycles_result.json

echo "=== Export Complete ==="