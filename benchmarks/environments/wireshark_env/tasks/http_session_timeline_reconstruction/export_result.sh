#!/bin/bash
set -e
echo "=== Exporting HTTP Session Timeline result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_FILE="/home/ga/Documents/captures/http_session_timeline.csv"
GT_DIR="/var/lib/task/ground_truth"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Initialization
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
HEADER_MATCH="false"
ROW_COUNT_MATCH="false"
CONTENT_MATCH_SCORE=0
ACTUAL_ROW_COUNT=0
GT_ROW_COUNT=$(cat "$GT_DIR/packet_count.txt" 2>/dev/null || echo "0")
EXPECTED_HEADER="frame_number,time_relative,source_ip,destination_ip,http_method,http_request_uri,http_host,http_response_code,http_content_type,frame_length"
ACTUAL_HEADER=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check Header
    ACTUAL_HEADER=$(head -n 1 "$OUTPUT_FILE" | tr -d '\r')
    if [ "$ACTUAL_HEADER" == "$EXPECTED_HEADER" ]; then
        HEADER_MATCH="true"
    fi

    # Check Row Count (excluding header)
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE")
    # If header exists, data rows = lines - 1. If empty or just header, 0.
    if [ "$TOTAL_LINES" -gt 0 ]; then
        ACTUAL_ROW_COUNT=$((TOTAL_LINES - 1))
    else
        ACTUAL_ROW_COUNT=0
    fi

    if [ "$ACTUAL_ROW_COUNT" -eq "$GT_ROW_COUNT" ]; then
        ROW_COUNT_MATCH="true"
    fi

    # Content Matching (Sampling)
    # We compare the data rows (skipping header) against ground truth data
    # We use python for flexible comparison (ignoring slight float diffs or quote styles if possible, 
    # but tshark CSV output is standard, so diff might work if they used the right flags).
    # Since agent instructions specify tshark, output should be very close.
    
    # Let's use a python script to calculate a match percentage
    CONTENT_MATCH_SCORE=$(python3 -c "
import sys
try:
    with open('$GT_DIR/ground_truth_data.csv', 'r') as f_gt:
        gt_lines = [l.strip() for l in f_gt.readlines() if l.strip()]
    
    # Read user output, skip header
    with open('$OUTPUT_FILE', 'r') as f_user:
        user_lines = f_user.readlines()
        if len(user_lines) > 0: user_lines = user_lines[1:] # Skip header
        user_lines = [l.strip() for l in user_lines if l.strip()]

    if not gt_lines:
        print(0)
        sys.exit(0)

    matches = 0
    # Create set for O(1) lookup or strictly compare indices?
    # Strict order is required by task ('ordered by frame number')
    
    limit = min(len(gt_lines), len(user_lines))
    for i in range(limit):
        # Allow slight formatting differences (e.g. quotes vs no quotes) if content same?
        # Tshark -E quote=d puts quotes around non-numerics usually.
        # Simple string comparison first
        if gt_lines[i] == user_lines[i]:
            matches += 1
        else:
            # Fallback: strict CSV parsing comparison could be done here if needed
            # For now, strict string match on tshark output is expected
            pass
            
    print(int((matches / len(gt_lines)) * 100))
except Exception as e:
    print(0)
")
else
    # File doesn't exist checks
    pass
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "header_match": $HEADER_MATCH,
    "row_count_match": $ROW_COUNT_MATCH,
    "actual_row_count": $ACTUAL_ROW_COUNT,
    "expected_row_count": $GT_ROW_COUNT,
    "content_match_score": $CONTENT_MATCH_SCORE,
    "actual_header": "$(echo "$ACTUAL_HEADER" | sed 's/"/\\"/g')",
    "expected_header": "$(echo "$EXPECTED_HEADER" | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="