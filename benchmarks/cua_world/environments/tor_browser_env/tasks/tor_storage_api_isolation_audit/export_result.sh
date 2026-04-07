#!/bin/bash
echo "=== Exporting tor_storage_api_isolation_audit results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Helper function to get file info and base64 content
get_file_info() {
    local file=$1
    if [ -f "$file" ]; then
        local size=$(stat -c %s "$file" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        local content=$(head -n 200 "$file" | base64 -w 0 2>/dev/null || echo "")
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"content_b64\": \"$content\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"content_b64\": \"\"}"
    fi
}

# Paths to evaluate
INDEX_HTML="/home/ga/web_audit/index.html"
SERVER_LOG="/home/ga/Documents/server.log"
INITIAL_TXT="/home/ga/Documents/initial_audit.txt"
RESTART_TXT="/home/ga/Documents/restart_audit.txt"

# Specifically check server.log for GET requests to the root
GET_REQUESTS=0
if [ -f "$SERVER_LOG" ]; then
    GET_REQUESTS=$(grep -c "GET / HTTP" "$SERVER_LOG" 2>/dev/null || echo "0")
fi

# Check if a python http.server is or was running
SERVER_PROCESS_FOUND="false"
if pgrep -f "python3 -m http.server" > /dev/null; then
    SERVER_PROCESS_FOUND="true"
fi

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "server_process_found": $SERVER_PROCESS_FOUND,
    "get_requests_count": $GET_REQUESTS,
    "index_html": $(get_file_info "$INDEX_HTML"),
    "server_log": $(get_file_info "$SERVER_LOG"),
    "initial_txt": $(get_file_info "$INITIAL_TXT"),
    "restart_txt": $(get_file_info "$RESTART_TXT"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="