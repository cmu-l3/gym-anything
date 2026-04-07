#!/bin/bash
# Export script for Audit Rated Disabilities task

echo "=== Exporting Audit Rated Disabilities Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check for Output File
OUTPUT_FILE="/home/ga/Documents/disability_audit.txt"
OUTPUT_EXISTS="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Read content safely
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | base64 -w 0)
fi

# 4. Generate Ground Truth (Dump all patients with disabilities to JSON)
# We create a temporary M script in the container to export data to JSON
echo "Generating ground truth data..."

cat << 'EOF' > /tmp/dump_disabilities.m
DUMP ;
 N DFN,IEN,NOD,PTR,PCT,DISNAME,PATNAME,FIRST,DFIRST,JSONSTR,ESC
 S FIRST=1
 W "{",!
 S DFN=0 F  S DFN=$O(^DPT(DFN)) Q:'DFN  D
 . I $D(^DPT(DFN,.372)) D
 . . S PATNAME=$P($G(^DPT(DFN,0)),"^",1)
 . . ; Escape quotes in patient name
 . . S PATNAME=$$ESC(PATNAME)
 . . I 'FIRST W ",",!
 . . S FIRST=0
 . . W """",PATNAME,""": ["
 . . S IEN=0,DFIRST=1 F  S IEN=$O(^DPT(DFN,.372,IEN)) Q:'IEN  D
 . . . S NOD=$G(^DPT(DFN,.372,IEN,0))
 . . . S PTR=$P(NOD,"^",1),PCT=$P(NOD,"^",2)
 . . . S DISNAME=$P($G(^DIC(31,PTR,0)),"^",1)
 . . . S DISNAME=$$ESC(DISNAME)
 . . . I 'DFIRST W ","
 . . . S DFIRST=0
 . . . W "{""disability"":""",DISNAME,""",""percent"":""",PCT,"""}"
 . . W "]"
 W !,"}"
 Q
ESC(S) ; Escape quotes
 N I,O S O=""
 F I=1:1:$L(S) S C=$E(S,I) S O=O_$S(C="""":"\""",1:C)
 Q O
EOF

# Copy script to container
docker cp /tmp/dump_disabilities.m vista-vehu:/home/vehu/dump_disabilities.m
docker exec -u root vista-vehu chown vehu:vehu /home/vehu/dump_disabilities.m

# Run the script and capture output to a file in the container, then copy out
docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run DUMP^dump_disabilities > /home/vehu/ground_truth_disabilities.json'

# Copy ground truth to host
docker cp vista-vehu:/home/vehu/ground_truth_disabilities.json /tmp/ground_truth_disabilities.json 2>/dev/null || echo "{}" > /tmp/ground_truth_disabilities.json

# 5. Check System State
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
fi

BROWSER_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|yottadb|ydbgui" | head -1 || echo "")
BROWSER_OPEN="false"
[ -n "$BROWSER_TITLE" ] && BROWSER_OPEN="true"

# 6. Create Result JSON
cat > /tmp/audit_disabilities_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_content_base64": "$FILE_CONTENT",
    "vista_status": "$VISTA_STATUS",
    "browser_open": $BROWSER_OPEN,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "Result saved to /tmp/audit_disabilities_result.json"