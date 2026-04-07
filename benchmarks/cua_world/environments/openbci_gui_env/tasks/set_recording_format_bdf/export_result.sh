#!/bin/bash
echo "=== Exporting set_recording_format_bdf results ==="

source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Capture final screenshot
take_screenshot /tmp/task_final.png

RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper function to check BDF header
check_bdf_header() {
    local file="$1"
    # Python script to check first byte (0xFF) and "BIOSEMI" string
    python3 -c "
import sys
try:
    with open('$file', 'rb') as f:
        header = f.read(8)
        # First byte should be 0xFF (255)
        # Next 7 bytes should be 'BIOSEMI'
        if header[0] == 255 and b'BIOSEMI' in header[1:]:
            print('true')
        else:
            print('false')
except:
    print('error')
"
}

# Find new BDF files
echo "Searching for new BDF files in $RECORDINGS_DIR..."
NEW_BDF_FOUND="false"
BDF_FILE_PATH=""
BDF_FILE_SIZE="0"
BDF_HEADER_VALID="false"

# Look for .bdf files recursively
while IFS= read -r file; do
    if [ -f "$file" ]; then
        MTIME=$(stat -c %Y "$file")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            echo "Found new BDF file: $file"
            NEW_BDF_FOUND="true"
            BDF_FILE_PATH="$file"
            BDF_FILE_SIZE=$(stat -c %s "$file")
            
            # Check header
            IS_VALID=$(check_bdf_header "$file")
            if [ "$IS_VALID" == "true" ]; then
                BDF_HEADER_VALID="true"
            fi
            
            # If we found a valid one, we can stop searching (or keep best)
            if [ "$BDF_HEADER_VALID" == "true" ]; then
                break
            fi
        fi
    fi
done < <(find "$RECORDINGS_DIR" -name "*.bdf" -type f)

# Check for new TXT files (to detect if user failed to change format)
NEW_TXT_FOUND="false"
TXT_FILE_COUNT=0
while IFS= read -r file; do
    if [ -f "$file" ]; then
        MTIME=$(stat -c %Y "$file")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            # Filter out non-recording text files if any (logs etc)
            # OpenBCI recordings usually have 'OpenBCI' in name
            if [[ "$file" == *"OpenBCI"* ]]; then
                NEW_TXT_FOUND="true"
                TXT_FILE_COUNT=$((TXT_FILE_COUNT + 1))
            fi
        fi
    fi
done < <(find "$RECORDINGS_DIR" -name "*.txt" -type f)

# Check if app is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "bdf_file_found": $NEW_BDF_FOUND,
    "bdf_file_path": "$BDF_FILE_PATH",
    "bdf_file_size_bytes": $BDF_FILE_SIZE,
    "bdf_header_valid": $BDF_HEADER_VALID,
    "txt_recording_found": $NEW_TXT_FOUND,
    "txt_recording_count": $TXT_FILE_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
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