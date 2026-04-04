#!/bin/bash
echo "=== Exporting Generate Patient Demographics Report Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Get Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze User Output File
OUTPUT_FILE="/home/ga/patient_report_count.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read first line, trim whitespace
    FILE_CONTENT=$(head -n 1 "$OUTPUT_FILE" | tr -d '[:space:]')
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Anti-gaming: Check if file was modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 4. Calculate Ground Truth (Dynamic DB Query)
# We query the database directly to find the exact number of patients matching criteria
# Criteria: Sex = Male AND DOB < 1960-01-01
echo "Calculating ground truth..."
GROUND_TRUTH_COUNT=$(librehealth_query "SELECT COUNT(*) FROM patient_data WHERE sex = 'Male' AND DOB < '1960-01-01' AND DOB IS NOT NULL AND DOB != ''")
# Fallback if query fails
if [ -z "$GROUND_TRUTH_COUNT" ]; then
    GROUND_TRUTH_COUNT="-1"
fi
echo "Ground Truth Count: $GROUND_TRUTH_COUNT"

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_content": "$FILE_CONTENT",
    "file_created_during_task": $CREATED_DURING_TASK,
    "ground_truth_count": $GROUND_TRUTH_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location (world readable for verifier)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="