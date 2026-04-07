#!/bin/bash
echo "=== Exporting Camera Coverage Gap Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. CAPTURE SYSTEM GROUND TRUTH
# We need to snapshot the actual system state via API so the verifier 
# can verify the agent's report against reality.
echo "Capturing ground truth system state..."

refresh_nx_token > /dev/null

# Get all data needed to reconstruct the gaps
ALL_CAMERAS=$(get_all_cameras)
ALL_LAYOUTS=$(get_all_layouts)
ALL_USERS=$(get_all_users)
SYSTEM_INFO=$(get_system_info)

# Save ground truth to a JSON file
cat > /tmp/ground_truth_state.json << EOF
{
  "cameras": $ALL_CAMERAS,
  "layouts": $ALL_LAYOUTS,
  "users": $ALL_USERS,
  "system_info": $SYSTEM_INFO,
  "timestamp": $(date +%s)
}
EOF

# 2. CHECK AGENT OUTPUT
OUTPUT_PATH="/home/ga/coverage_gap_report.json"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT="{}"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content if valid JSON
    if jq . "$OUTPUT_PATH" >/dev/null 2>&1; then
        REPORT_CONTENT=$(cat "$OUTPUT_PATH")
    fi
fi

# 3. TAKE FINAL SCREENSHOT
take_screenshot /tmp/task_final.png

# 4. PREPARE EXPORT JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_preview": "See full file copy",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result JSON
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy agent report and ground truth for verifier to pick up
cp "$OUTPUT_PATH" /tmp/agent_report.json 2>/dev/null || echo "{}" > /tmp/agent_report.json
chmod 666 /tmp/agent_report.json
chmod 666 /tmp/ground_truth_state.json

echo "=== Export complete ==="