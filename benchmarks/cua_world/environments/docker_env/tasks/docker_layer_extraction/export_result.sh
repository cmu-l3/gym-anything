#!/bin/bash
# Export script for docker_layer_extraction task
echo "=== Exporting Forensics Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GROUND_TRUTH_HASH=$(cat /tmp/ground_truth_hash.txt 2>/dev/null || echo "")
RECOVERY_PATH="/home/ga/Desktop/risk_model.py"

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_HASH=""
FILE_CREATED_DURING_TASK="false"
CONTENT_MATCH_SCORE=0
STRINGS_FOUND=0

# Check if file exists
if [ -f "$RECOVERY_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RECOVERY_PATH")
    
    # Check creation time
    FILE_MTIME=$(stat -c %Y "$RECOVERY_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Calculate hash
    FILE_HASH=$(sha256sum "$RECOVERY_PATH" | awk '{print $1}')
    
    # Check for specific proprietary strings (grep returns 0 on match)
    grep -Fq "class CreditRiskScorer" "$RECOVERY_PATH" && ((STRINGS_FOUND++))
    grep -Fq "self._income_weight = 0.85" "$RECOVERY_PATH" && ((STRINGS_FOUND++))
    grep -Fq "CONFIDENTIAL" "$RECOVERY_PATH" && ((STRINGS_FOUND++))
    
    # Calculate content match percentage (3 strings = 100%)
    if [ "$STRINGS_FOUND" -eq 3 ]; then
        CONTENT_MATCH_SCORE=100
    elif [ "$STRINGS_FOUND" -eq 2 ]; then
        CONTENT_MATCH_SCORE=66
    elif [ "$STRINGS_FOUND" -eq 1 ]; then
        CONTENT_MATCH_SCORE=33
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Export result to JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_hash": "$FILE_HASH",
    "ground_truth_hash": "$GROUND_TRUTH_HASH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "strings_found_count": $STRINGS_FOUND,
    "content_match_score": $CONTENT_MATCH_SCORE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="