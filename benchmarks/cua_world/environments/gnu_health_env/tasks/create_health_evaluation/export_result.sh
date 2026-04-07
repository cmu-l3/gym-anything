#!/bin/bash
echo "=== Exporting create_health_evaluation task result ==="

source /workspace/scripts/task_utils.sh

# Wait for any pending DB writes
sleep 3

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Retrieve stored baseline values
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_EVAL_COUNT=$(cat /tmp/initial_eval_count.txt 2>/dev/null || echo "0")
ANA_PATIENT_ID=$(cat /tmp/ana_patient_id.txt 2>/dev/null || echo "")

# Current evaluation count
CURRENT_EVAL_COUNT=$(gnuhealth_count "gnuhealth_patient_evaluation" 2>/dev/null || echo "0")
echo "Evaluation count: before=$INITIAL_EVAL_COUNT, after=$CURRENT_EVAL_COUNT"
NEW_EVALS=$((CURRENT_EVAL_COUNT - INITIAL_EVAL_COUNT))

ANA_EVAL_FOUND="false"
CC_MATCH="false"
PI_MATCH="false"
META_MATCH="false"

if [ -n "$ANA_PATIENT_ID" ] && [ "${NEW_EVALS:-0}" -gt 0 ]; then
    # Look for evaluation for Ana Betz created after task start
    NEW_EVAL_DATA=$(gnuhealth_db_query "
        SELECT id, COALESCE(chief_complaint, ''), COALESCE(present_illness, ''),
               COALESCE(evaluation_type, ''), COALESCE(urgency, '')
        FROM gnuhealth_patient_evaluation
        WHERE patient = ${ANA_PATIENT_ID} AND id > ${INITIAL_EVAL_COUNT}
        ORDER BY id DESC LIMIT 1
    " 2>/dev/null)

    if [ -n "$NEW_EVAL_DATA" ]; then
        ANA_EVAL_FOUND="true"
        CC=$(echo "$NEW_EVAL_DATA" | awk -F'|' '{print $2}')
        PI=$(echo "$NEW_EVAL_DATA" | awk -F'|' '{print $3}')
        EVAL_TYPE=$(echo "$NEW_EVAL_DATA" | awk -F'|' '{print $4}')
        URGENCY=$(echo "$NEW_EVAL_DATA" | awk -F'|' '{print $5}')
        
        if echo "$CC" | grep -qi "laceration"; then
            CC_MATCH="true"
        fi
        
        # Check if present illness is not empty and reasonably long
        if [ ${#PI} -gt 10 ]; then
            PI_MATCH="true"
        fi
        
        if [ -n "$EVAL_TYPE" ] || [ -n "$URGENCY" ]; then
            META_MATCH="true"
        fi
    else
        # Try to find if any new evaluation has laceration (wrong patient case)
        ANY_EVAL_DATA=$(gnuhealth_db_query "
            SELECT id, COALESCE(chief_complaint, ''), COALESCE(present_illness, ''),
                   COALESCE(evaluation_type, ''), COALESCE(urgency, '')
            FROM gnuhealth_patient_evaluation
            WHERE id > ${INITIAL_EVAL_COUNT}
            ORDER BY id DESC LIMIT 1
        " 2>/dev/null)
        
        if [ -n "$ANY_EVAL_DATA" ]; then
            CC=$(echo "$ANY_EVAL_DATA" | awk -F'|' '{print $2}')
            PI=$(echo "$ANY_EVAL_DATA" | awk -F'|' '{print $3}')
            EVAL_TYPE=$(echo "$ANY_EVAL_DATA" | awk -F'|' '{print $4}')
            URGENCY=$(echo "$ANY_EVAL_DATA" | awk -F'|' '{print $5}')
            
            if echo "$CC" | grep -qi "laceration"; then
                CC_MATCH="true"
            fi
            
            if [ ${#PI} -gt 10 ]; then
                PI_MATCH="true"
            fi
            
            if [ -n "$EVAL_TYPE" ] || [ -n "$URGENCY" ]; then
                META_MATCH="true"
            fi
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_eval_count": $INITIAL_EVAL_COUNT,
    "current_eval_count": $CURRENT_EVAL_COUNT,
    "new_evals_count": $NEW_EVALS,
    "ana_patient_id": "$ANA_PATIENT_ID",
    "ana_eval_found": $ANA_EVAL_FOUND,
    "cc_match": $CC_MATCH,
    "pi_match": $PI_MATCH,
    "meta_match": $META_MATCH,
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="