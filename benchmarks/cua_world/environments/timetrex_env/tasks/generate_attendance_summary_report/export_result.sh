#!/bin/bash
echo "=== Exporting generate_attendance_summary_report Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers() {
        docker ps | grep -q timetrex || docker start timetrex timetrex-postgres 2>/dev/null || true
        sleep 3
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

ensure_docker_containers
take_screenshot /tmp/generate_attendance_summary_report_end_screenshot.png

TASK_START=$(cat /tmp/generate_attendance_summary_report_start_ts 2>/dev/null || echo "0")

TARGET_FILE="/home/ga/Desktop/attendance_feb2026.csv"

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_SIZE=0
LINE_COUNT=0
HAS_CONTENT=false

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    LINE_COUNT=$(wc -l < "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$LINE_COUNT" -gt 1 ]; then
        HAS_CONTENT=true
    fi
fi

echo "File exists=$FILE_EXISTS new=$FILE_IS_NEW size=$FILE_SIZE lines=$LINE_COUNT"

# Also check Downloads folder as a fallback (agent might have saved there)
DOWNLOADS_FILE="/home/ga/Downloads/attendance_feb2026.csv"
DOWNLOADS_EXISTS=false
if [ -f "$DOWNLOADS_FILE" ]; then
    DL_MTIME=$(stat -c %Y "$DOWNLOADS_FILE" 2>/dev/null || echo "0")
    if [ "$DL_MTIME" -gt "$TASK_START" ]; then
        DOWNLOADS_EXISTS=true
    fi
fi

RESULT_JSON=$(mktemp)
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_size_bytes": $FILE_SIZE,
    "line_count": $LINE_COUNT,
    "has_content": $HAS_CONTENT,
    "downloads_fallback": $DOWNLOADS_EXISTS
}
EOF

cp "$RESULT_JSON" /tmp/generate_attendance_summary_report_result.json
chmod 666 /tmp/generate_attendance_summary_report_result.json
rm -f "$RESULT_JSON"

echo "=== Export Complete ==="
