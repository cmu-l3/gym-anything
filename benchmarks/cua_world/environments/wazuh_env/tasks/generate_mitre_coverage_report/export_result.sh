#!/bin/bash
echo "=== Exporting MITRE Coverage Report Result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/reports/mitre_coverage_report.json"

# --- 1. Check User Output ---
if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    # Copy report to temp location for export
    cp "$REPORT_PATH" /tmp/user_report.json
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    echo "{}" > /tmp/user_report.json
fi

# --- 2. Generate Ground Truth (for verification) ---
# We query the API ourselves to know what the correct values should roughly be.
# This prevents hardcoding values that might change with rule updates.

echo "Generating ground truth data..."
TOKEN=$(get_api_token)
GROUND_TRUTH_FILE="/tmp/ground_truth.json"

if [ -n "$TOKEN" ]; then
    # Get total rules with MITRE mappings
    # Using a query to filter rules that have 'mitre' field
    # Note: The /rules endpoint might not support 'exists' query directly in all versions,
    # but we can get a general count or check specific technique counts.
    
    # Ground Truth Metric 1: Count of rules for specific techniques (spot checks)
    # T1110 (Brute Force), T1053 (Scheduled Task), T1059 (Command/Scripting)
    COUNT_T1110=$(wazuh_api GET "/rules?mitre.id=T1110&count=true" | jq .data.total_affected_items 2>/dev/null || echo 0)
    COUNT_T1053=$(wazuh_api GET "/rules?mitre.id=T1053&count=true" | jq .data.total_affected_items 2>/dev/null || echo 0)
    COUNT_T1059=$(wazuh_api GET "/rules?mitre.id=T1059&count=true" | jq .data.total_affected_items 2>/dev/null || echo 0)
    
    # Ground Truth Metric 2: Approximate total MITRE rules
    # This is harder to get exact via one API call without heavy processing, 
    # but we can get a rough estimate or just rely on the spot checks.
    # We will trust the spot checks for precision verification.
    
    cat > "$GROUND_TRUTH_FILE" << EOF
{
    "t1110_count": $COUNT_T1110,
    "t1053_count": $COUNT_T1053,
    "t1059_count": $COUNT_T1059,
    "api_accessible": true
}
EOF
else
    echo "Failed to get API token for ground truth generation"
    cat > "$GROUND_TRUTH_FILE" << EOF
{
    "t1110_count": 0,
    "t1053_count": 0,
    "t1059_count": 0,
    "api_accessible": false
}
EOF
fi

# --- 3. Create Final Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Combine user report status and ground truth
# We embed the user report content (if small) or just status
jq -n \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg exists "$OUTPUT_EXISTS" \
    --arg fresh "$FILE_CREATED_DURING_TASK" \
    --slurpfile ground_truth "$GROUND_TRUTH_FILE" \
    --slurpfile user_report /tmp/user_report.json \
    '{
        task_start: $start,
        task_end: $end,
        output_exists: ($exists == "true"),
        file_created_during_task: ($fresh == "true"),
        ground_truth: $ground_truth[0],
        user_report_content: $user_report[0]
    }' > "$TEMP_JSON"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" "/tmp/user_report.json" "$GROUND_TRUTH_FILE"

echo "Export complete. Result saved to /tmp/task_result.json"