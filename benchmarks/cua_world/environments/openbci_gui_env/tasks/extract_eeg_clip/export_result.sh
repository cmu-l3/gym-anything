#!/bin/bash
echo "=== Exporting extract_eeg_clip results ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
SOURCE_FILE="OpenBCI-EEG-S001-MotorImagery.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Identify new files
# We look for files created/modified AFTER task start
# Excluding the source file itself
NEW_FILE=""
NEW_FILE_SIZE=0
NEW_FILE_LINES=0
NEW_FILE_MTIME=0

# Find files modified after start time
# OpenBCI usually creates a directory or a txt file
# We look for .txt or .csv files in the recordings dir (recursive)
echo "Searching for new recording files..."
while IFS= read -r file; do
    # Skip the source file
    if [[ "$file" == *"$SOURCE_FILE" ]]; then
        continue
    fi
    
    # Check modification time
    MTIME=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    
    if [ "$MTIME" -gt "$TASK_START" ]; then
        echo "Found candidate new file: $file"
        NEW_FILE="$file"
        NEW_FILE_MTIME="$MTIME"
        NEW_FILE_SIZE=$(stat -c %s "$file" 2>/dev/null || echo 0)
        # Count lines (samples)
        # Subtract header lines (lines starting with %)
        TOTAL_LINES=$(wc -l < "$file" 2>/dev/null || echo 0)
        HEADER_LINES=$(grep -c "^%" "$file" 2>/dev/null || echo 0)
        NEW_FILE_LINES=$((TOTAL_LINES - HEADER_LINES))
        
        # If we found a substantial file, we assume this is the recording
        # (Agents might create multiple small ones, we take the largest/last one)
        break 
    fi
done < <(find "$RECORDINGS_DIR" -type f -name "*.txt" -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)

# Check if App is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_created": $([ -n "$NEW_FILE" ] && echo "true" || echo "false"),
    "file_path": "$NEW_FILE",
    "file_size_bytes": $NEW_FILE_SIZE,
    "sample_count": $NEW_FILE_LINES,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json