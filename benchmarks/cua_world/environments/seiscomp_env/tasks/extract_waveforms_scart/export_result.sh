#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/extracted_BKB_BHZ.mseed"

EXISTS="false"
SIZE=0
MTIME=0
HAS_GE="false"
HAS_BKB="false"
HAS_BHZ="false"
PARSEABLE="false"
SCMSSORT_OUTPUT=""

# Check the file state and contents
if [ -f "$OUTPUT_FILE" ]; then
    EXISTS="true"
    SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Binary/String content heuristics
    if strings "$OUTPUT_FILE" 2>/dev/null | grep -q "GE"; then HAS_GE="true"; fi
    if strings "$OUTPUT_FILE" 2>/dev/null | grep -q "BKB"; then HAS_BKB="true"; fi
    if strings "$OUTPUT_FILE" 2>/dev/null | grep -q "BHZ"; then HAS_BHZ="true"; fi
    
    # Tool validation using SeisComP's built-in miniSEED parser
    SCMSSORT="$SEISCOMP_ROOT/bin/scmssort"
    if [ -x "$SCMSSORT" ]; then
        # Check if scmssort can read it and outputs the expected station code
        SORT_OUT=$($SCMSSORT --list "$OUTPUT_FILE" 2>/dev/null || true)
        if echo "$SORT_OUT" | grep -q "BKB"; then
            PARSEABLE="true"
            # Capture the first few lines of parser output as evidence
            SCMSSORT_OUTPUT=$(echo "$SORT_OUT" | head -n 3 | tr '\n' ' ' | tr -d '"')
        fi
    fi
fi

# Take final state screenshot
take_screenshot /tmp/task_final.png

# Create JSON payload securely using a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $EXISTS,
    "file_size": $SIZE,
    "file_mtime": $MTIME,
    "has_ge": $HAS_GE,
    "has_bkb": $HAS_BKB,
    "has_bhz": $HAS_BHZ,
    "parseable": $PARSEABLE,
    "scmssort_sample": "$SCMSSORT_OUTPUT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location ensuring proper read access
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="