#!/bin/bash
echo "=== Exporting task result ==="

# Take final state screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check for evidence file (.py or .sam)
EVIDENCE_EXISTS="false"
EVIDENCE_MODIFIED="false"
EVIDENCE_FILE=""

# Check in Documents/SAM_Projects
for ext in "py" "sam"; do
    FILES=$(find /home/ga/Documents/SAM_Projects -maxdepth 1 -name "*.$ext" 2>/dev/null)
    for f in $FILES; do
        if [ -f "$f" ]; then
            EVIDENCE_EXISTS="true"
            EVIDENCE_FILE="$f"
            FTIME=$(stat -c%Y "$f" 2>/dev/null || echo "0")
            if [ "$FTIME" -gt "$TASK_START" ]; then
                EVIDENCE_MODIFIED="true"
                break 2
            fi
        fi
    done
done

# Check expected JSON output
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/technology_comparison.json"
FILE_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create JSON metadata safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson evidence_exists "$EVIDENCE_EXISTS" \
    --argjson evidence_modified "$EVIDENCE_MODIFIED" \
    --arg evidence_file "$EVIDENCE_FILE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        evidence_exists: $evidence_exists,
        evidence_modified: $evidence_modified,
        evidence_file: $evidence_file,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="