#!/bin/bash
echo "=== Exporting Generate Fleet QR Codes results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_COUNT=$(cat /tmp/expected_aircraft_count.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/Documents/fleet_tags"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if qrcode library is installed
PIP_CHECK_SYSTEM=$(pip freeze | grep -i qrcode || echo "")
PIP_CHECK_VENV=$(/opt/aerobridge_venv/bin/pip freeze | grep -i qrcode || echo "")
LIB_INSTALLED="false"
if [ -n "$PIP_CHECK_SYSTEM" ] || [ -n "$PIP_CHECK_VENV" ]; then
    LIB_INSTALLED="true"
fi

# 2. Analyze generated files
FILE_COUNT=0
VALID_FILENAMES=0
SAMPLE_DECODED_URL=""
SAMPLE_FILE=""
FILES_CREATED_DURING_TASK="false"

if [ -d "$OUTPUT_DIR" ]; then
    FILE_COUNT=$(ls -1 "$OUTPUT_DIR"/*.png 2>/dev/null | wc -l)
    
    # Check naming convention (tag_*.png)
    VALID_FILENAMES=$(ls -1 "$OUTPUT_DIR"/tag_*.png 2>/dev/null | wc -l)
    
    # Check timestamps and get a sample file
    SAMPLE_FILE=$(ls -1 "$OUTPUT_DIR"/tag_*.png 2>/dev/null | head -1)
    
    if [ -n "$SAMPLE_FILE" ]; then
        FILE_MTIME=$(stat -c %Y "$SAMPLE_FILE" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            FILES_CREATED_DURING_TASK="true"
        fi
        
        # Try to decode QR code using zbar-tools (if installed) or python
        # We'll rely on python in the verifier or inline here if possible
        # Installing zbarimg for robust decoding inside container
        if ! command -v zbarimg &> /dev/null; then
             apt-get update && apt-get install -y zbar-tools >/dev/null 2>&1 || true
        fi
        
        if command -v zbarimg &> /dev/null; then
            DECODED=$(zbarimg -q --raw "$SAMPLE_FILE" 2>/dev/null || echo "")
            SAMPLE_DECODED_URL="$DECODED"
        fi
    fi
fi

# 3. Check for generation script
SCRIPT_EXISTS="false"
SCRIPT_PATH=""
# Look for python scripts created during task in common locations
CANDIDATE_SCRIPTS=$(find /home/ga -name "*.py" -newermt "@$TASK_START" 2>/dev/null)
if [ -n "$CANDIDATE_SCRIPTS" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_PATH=$(echo "$CANDIDATE_SCRIPTS" | head -1)
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "expected_count": $EXPECTED_COUNT,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false"),
    "file_count": $FILE_COUNT,
    "valid_filename_count": $VALID_FILENAMES,
    "lib_installed": $LIB_INSTALLED,
    "sample_file_exists": $([ -n "$SAMPLE_FILE" ] && echo "true" || echo "false"),
    "sample_decoded_url": "$SAMPLE_DECODED_URL",
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "script_created": $SCRIPT_EXISTS,
    "script_path": "$SCRIPT_PATH"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="