#!/bin/bash
echo "=== Exporting upload_scanned_document results ==="

# Load setup artifacts
PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_doc_count.txt 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query current document state
if [ "$PID" != "0" ]; then
    # Get current count
    FINAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM documents WHERE pid=$PID")
    
    # Get the most recently added document for this patient
    # We select specific fields to verify the content
    LATEST_DOC_JSON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT JSON_OBJECT('id', documents_id, 'description', documents_desc, 'url', documents_url, 'date', date) FROM documents WHERE pid=$PID ORDER BY documents_id DESC LIMIT 1" 2>/dev/null)
else
    FINAL_COUNT="0"
    LATEST_DOC_JSON="null"
fi

# Sanitize JSON output from mysql (sometimes it adds escape chars)
if [ -z "$LATEST_DOC_JSON" ]; then
    LATEST_DOC_JSON="null"
fi

# Determine if NOSH is running
APP_RUNNING="false"
if curl -s http://localhost/login > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $START_TIME,
    "task_end": $TASK_END,
    "target_pid": $PID,
    "initial_doc_count": $INITIAL_COUNT,
    "final_doc_count": $FINAL_COUNT,
    "latest_document": $LATEST_DOC_JSON,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive rights
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="