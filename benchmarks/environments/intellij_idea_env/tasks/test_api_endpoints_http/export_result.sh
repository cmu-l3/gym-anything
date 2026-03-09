#!/bin/bash
echo "=== Exporting API Testing Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PROJECT_DIR="/home/ga/IdeaProjects/LibraryClient"
LOG_FILE="/tmp/library_server_access.log"
OUTPUT_JSON="/tmp/task_result.json"

# 1. Find the .http file (allow some flexibility in naming)
HTTP_FILE=""
HTTP_CONTENT=""
HTTP_FILE_NAME=""

# Check expected name first
if [ -f "$PROJECT_DIR/library_tests.http" ]; then
    HTTP_FILE="$PROJECT_DIR/library_tests.http"
    HTTP_FILE_NAME="library_tests.http"
else
    # Find any .http file in project
    FOUND=$(find "$PROJECT_DIR" -name "*.http" -type f | head -n 1)
    if [ -n "$FOUND" ]; then
        HTTP_FILE="$FOUND"
        HTTP_FILE_NAME=$(basename "$FOUND")
    fi
fi

if [ -n "$HTTP_FILE" ]; then
    HTTP_CONTENT=$(cat "$HTTP_FILE")
    HTTP_EXISTS="true"
else
    HTTP_EXISTS="false"
fi

# 2. Read Server Logs
SERVER_LOGS=""
if [ -f "$LOG_FILE" ]; then
    SERVER_LOGS=$(cat "$LOG_FILE")
fi

# 3. Verify Server Status (was it still running?)
SERVER_RUNNING="false"
if netstat -tulpn | grep -q 8081; then
    SERVER_RUNNING="true"
fi

# 4. Create Result JSON
# Use python for safe JSON encoding
python3 -c "
import json
import os
import sys

try:
    http_content = '''$HTTP_CONTENT'''
    server_logs = '''$SERVER_LOGS'''
except:
    http_content = ''
    server_logs = ''

result = {
    'http_file_exists': $HTTP_EXISTS,
    'http_file_name': '$HTTP_FILE_NAME',
    'http_content': http_content,
    'server_logs': server_logs,
    'server_running': $SERVER_RUNNING,
    'timestamp': '$(date -Iseconds)'
}

with open('$OUTPUT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Clean up: Stop the server
if [ -f /tmp/server_pid.txt ]; then
    kill $(cat /tmp/server_pid.txt) 2>/dev/null || true
fi

echo "Result saved to $OUTPUT_JSON"
cat "$OUTPUT_JSON"
echo "=== Export complete ==="