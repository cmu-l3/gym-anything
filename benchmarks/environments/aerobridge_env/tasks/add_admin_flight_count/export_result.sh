#!/bin/bash
# export_result.sh — post_task hook for add_admin_flight_count

echo "=== Exporting add_admin_flight_count result ==="

# 1. Capture final screenshot
source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final.png

# 2. Collect timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ADMIN_FILE="/opt/aerobridge/registry/admin.py"
FILE_MTIME=$(stat -c %Y "$ADMIN_FILE" 2>/dev/null || echo "0")

# 3. Read file content for static analysis
# We base64 encode it to safely put it in JSON
FILE_CONTENT_B64=""
if [ -f "$ADMIN_FILE" ]; then
    FILE_CONTENT_B64=$(base64 -w 0 "$ADMIN_FILE")
fi

# 4. Check if Server is running
SERVER_RUNNING="false"
if pgrep -f "runserver" > /dev/null; then
    SERVER_RUNNING="true"
fi

# 5. Dynamic Check: Curl the admin page and check for the column header
# We need to log in first to see the admin list
echo "Checking admin page content..."
PAGE_HAS_HEADER="false"
PAGE_HAS_COUNTS="false"

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

# Use Python to log in and fetch the page content
PYTHON_CHECK_SCRIPT=$(cat << 'PYEOF'
import requests
import sys

try:
    client = requests.Session()
    # Get login page for CSRF
    login_url = "http://localhost:8000/admin/login/"
    r1 = client.get(login_url)
    csrf = client.cookies['csrftoken']
    
    # Perform Login
    login_data = {
        'username': 'admin',
        'password': 'adminpass123',
        'csrfmiddlewaretoken': csrf,
        'next': '/admin/registry/aircraft/'
    }
    r2 = client.post(login_url, data=login_data, headers={'Referer': login_url})
    
    # Check Content
    html = r2.text
    
    has_header = "Plan Count" in html
    # We injected 3 plans in setup, so look for the number '3' in a column pattern
    # This is a loose check, but better than nothing
    has_counts = '<td class="field-flight_plan_count">3</td>' in html or '<td class="field-plan_count">3</td>' in html or '>3<' in html
    
    print(f"{'true' if has_header else 'false'}|{'true' if has_counts else 'false'}")
except Exception as e:
    print("false|false")
PYEOF
)

CHECK_RESULT=$(/opt/aerobridge_venv/bin/python3 -c "$PYTHON_CHECK_SCRIPT")
PAGE_HAS_HEADER=$(echo "$CHECK_RESULT" | cut -d'|' -f1)
PAGE_HAS_COUNTS=$(echo "$CHECK_RESULT" | cut -d'|' -f2)

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_mtime": $FILE_MTIME,
    "file_content_b64": "$FILE_CONTENT_B64",
    "server_running": $SERVER_RUNNING,
    "page_has_header": $PAGE_HAS_HEADER,
    "page_has_counts": $PAGE_HAS_COUNTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="