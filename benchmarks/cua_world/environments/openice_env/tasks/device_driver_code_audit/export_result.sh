#!/bin/bash
echo "=== Exporting Device Driver Code Audit result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Report file details
REPORT_PATH="/home/ga/Desktop/device_driver_audit.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT=""
VALID_PATHS_FOUND=0
MANUFACTURERS_FOUND=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Read content safely (limit size)
    REPORT_CONTENT=$(head -c 5000 "$REPORT_PATH" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Analyze paths in the report
    # We look for lines containing /opt/openice and check if those paths exist
    while IFS= read -r line; do
        # Extract potential path starting with /opt/openice
        extracted_path=$(echo "$line" | grep -o "/opt/openice[^ ]*")
        
        if [ -n "$extracted_path" ]; then
            # Check if path exists
            if [ -d "$extracted_path" ] || [ -f "$extracted_path" ]; then
                VALID_PATHS_FOUND=$((VALID_PATHS_FOUND + 1))
            fi
        fi
        
        # Count manufacturers (simple keyword check)
        if echo "$line" | grep -qiE "Manufacturer|Brand"; then
            MANUFACTURERS_FOUND=$((MANUFACTURERS_FOUND + 1))
        fi
    done < "$REPORT_PATH"
fi

# Check OpenICE status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Create result JSON
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_content": "$REPORT_CONTENT",
    "valid_paths_found": $VALID_PATHS_FOUND,
    "manufacturers_count": $MANUFACTURERS_FOUND,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
echo "Report exists: $REPORT_EXISTS"
echo "Valid paths confirmed: $VALID_PATHS_FOUND"
echo "Manufacturers entries: $MANUFACTURERS_FOUND"
cat /tmp/task_result.json