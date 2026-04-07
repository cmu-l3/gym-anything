#!/bin/bash
echo "=== Exporting dicom_network_send task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
LOG_FILE="/tmp/pacs_server.log"
TARGET_DIR="/home/ga/DICOM/pacs_archive"

# Initialize metrics
ASSOC_COUNT=0
STORE_COUNT=0
FILE_COUNT=0
LOG_SNIPPET=""

# Check network protocol logs for evidence of DICOM transfer
if [ -f "$LOG_FILE" ]; then
    # Look for association requests
    ASSOC_COUNT=$(grep -iE "Association Received|Receiving Association" "$LOG_FILE" 2>/dev/null | wc -l || echo "0")
    
    # Look for C-STORE requests (actual image transfer)
    STORE_COUNT=$(grep -iE "Store Request|C-STORE" "$LOG_FILE" 2>/dev/null | wc -l || echo "0")
    
    # Extract the last few lines for debugging context (safely escape for JSON)
    LOG_SNIPPET=$(tail -n 15 "$LOG_FILE" 2>/dev/null | tr -d '\000-\031' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ')
fi

# Check if any DICOM files were actually received and saved to disk
if [ -d "$TARGET_DIR" ]; then
    FILE_COUNT=$(find "$TARGET_DIR" -type f \( -name "*.dcm" -o -name "*.DCM" -o -name "*.img" -o -not -name ".*" \) 2>/dev/null | wc -l || echo "0")
fi

# Create result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "association_count": $ASSOC_COUNT,
    "store_count": $STORE_COUNT,
    "file_count": $FILE_COUNT,
    "log_snippet": "$LOG_SNIPPET",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="