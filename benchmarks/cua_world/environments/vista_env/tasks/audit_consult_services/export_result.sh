#!/bin/bash
# Export script for Audit Consult Services task

echo "=== Exporting Audit Consult Services Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true
echo "Final screenshot saved"

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Output File
OUTPUT_FILE="/home/ga/Documents/consult_services_audit.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Verify file was modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Generate Ground Truth (Valid Service Names) from VistA
# Query ^GMR(123.5) for all service names to validate user input
echo "Generating ground truth from VistA database..."

# M/MUMPS Command: Iterate ^GMR(123.5) and print the first piece (Service Name)
GROUND_TRUTH_CMD='S U="^",X=0 F  S X=$O(^GMR(123.5,X)) Q:X=""  W $P($G(^GMR(123.5,X,0)),U,1),!'

# Execute command inside container
VALID_SERVICES=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD '$GROUND_TRUTH_CMD'" 2>/dev/null)

# Save valid services to a temp file for the verifier to read
echo "$VALID_SERVICES" > /tmp/valid_consult_services.txt

# 5. Browser State Check
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
if [ -n "$BROWSER_TITLE" ]; then
    BROWSER_OPEN="true"
fi

# 6. Escape strings for JSON
if ! type escape_json &>/dev/null; then
    escape_json() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
    }
fi
BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")

# 7. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "browser_window_open": $BROWSER_OPEN,
    "browser_window_title": "$BROWSER_TITLE_ESC",
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "output_file_path": "$OUTPUT_FILE",
    "ground_truth_path": "/tmp/valid_consult_services.txt"
}
EOF

# Set permissions so verifier (running as different user) can read
chmod 644 /tmp/task_result.json /tmp/valid_consult_services.txt "$OUTPUT_FILE" 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export Complete ==="