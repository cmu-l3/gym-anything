#!/bin/bash
# Export script for Cross-System Patient Data Completeness task

echo "=== Exporting Cross-System Patient Data Completeness Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="stopped"
else
    VISTA_STATUS="not_found"
fi

CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null || docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)

YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

OUTPUT_FILE="/home/ga/Desktop/patient_profile.txt"
OUTPUT_EXISTS="false"
OUTPUT_MTIME=0
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

FILE_IS_NEW="false"
if [ "$OUTPUT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    FILE_IS_NEW="true"
fi

cat > /tmp/cross_system_patient_data_completeness_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_container_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "output_file": {
        "path": "$OUTPUT_FILE",
        "exists": $OUTPUT_EXISTS,
        "mtime": $OUTPUT_MTIME,
        "size_bytes": $OUTPUT_SIZE,
        "created_during_task": $FILE_IS_NEW
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "Result saved to /tmp/cross_system_patient_data_completeness_result.json"
cat /tmp/cross_system_patient_data_completeness_result.json

echo ""
echo "=== Export Complete ==="
