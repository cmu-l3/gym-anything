#!/bin/bash
# Export script for Audit VA Drug Classifications
# Verifies file creation and extracts ground truth data for verifier comparison.

echo "=== Exporting Audit Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/drug_class_audit.txt"

# 1. Take final screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_final.png
else
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true
fi

# 2. Check Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (base64 encode to safe transport in JSON)
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH" | base64 -w 0)
fi

# 3. Extract Ground Truth from Database for Verification
# We fetch a sample of codes including CN/CV to valid against user input
echo "Extracting ground truth..."

# Query for CN codes
GT_CN_DATA=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S X=\"CN\" F  S X=\$O(^PS(50.605,\"B\",X)) Q:X=\"\"!(\$E(X,1,2)'\''=\"CN\")  S IEN=\$O(^PS(50.605,\"B\",X,0)) W X,\"^\",\$P(\$G(^PS(50.605,IEN,0)),\"^\",2),\"|\""' 2>/dev/null)

# Query for CV codes
GT_CV_DATA=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S X=\"CV\" F  S X=\$O(^PS(50.605,\"B\",X)) Q:X=\"\"!(\$E(X,1,2)'\''=\"CV\")  S IEN=\$O(^PS(50.605,\"B\",X,0)) W X,\"^\",\$P(\$G(^PS(50.605,IEN,0)),\"^\",2),\"|\""' 2>/dev/null)

# Get a few random others for general validation
GT_SAMPLE=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S X=0,N=0 F  S X=\$O(^PS(50.605,X)) Q:X=\"\"!(N>20)  S N=N+1 W \$P(\$G(^PS(50.605,X,0)),\"^\",1),\"^\",\$P(\$G(^PS(50.605,X,0)),\"^\",2),\"|\""' 2>/dev/null)

# Combine and escape
FULL_GT="${GT_CN_DATA}|${GT_CV_DATA}|${GT_SAMPLE}"

# Escape for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

FULL_GT_ESC=$(escape_json "$FULL_GT")
BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_TITLE_ESC=$(escape_json "$BROWSER_TITLE")

# 4. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_content_b64": "$OUTPUT_CONTENT",
    "ground_truth_data": "$FULL_GT_ESC",
    "browser_title": "$BROWSER_TITLE_ESC",
    "vista_running": $(docker ps -q -f name=vista-vehu | grep -q . && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"