#!/bin/bash
# export_result.sh — post_task hook for customize_admin_branding
# Verifies the task by querying the running web server and checking HTML content.

echo "=== Exporting customize_admin_branding result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if server is running
SERVER_RUNNING="false"
HTTP_STATUS="000"

if pgrep -f "manage.py runserver" > /dev/null; then
    SERVER_RUNNING="true"
fi

# 3. Fetch the Admin Login Page (checks site_header and site_title)
LOGIN_URL="http://localhost:8000/admin/login/"
LOGIN_HTML=$(curl -s -L "$LOGIN_URL")
LOGIN_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$LOGIN_URL")

# 4. Fetch the Admin Dashboard (checks index_title)
# Note: We might be redirected to login if not authenticated, but the login page 
# usually doesn't show the index_title ("Site Administration" vs "Fleet Command Center").
# However, if the agent logged in, we can see it.
# Even if not logged in, we verify what we can. 
# We'll attempt to access the admin root.
ADMIN_URL="http://localhost:8000/admin/"
ADMIN_HTML=$(curl -s -L "$ADMIN_URL")

# 5. Check for specific strings in the HTML
# Expected: "SkyGuard Operations", "SkyGuard Admin", "Fleet Command Center"

FOUND_HEADER="false"
if echo "$LOGIN_HTML" | grep -q "SkyGuard Operations"; then
    FOUND_HEADER="true"
fi

FOUND_TITLE="false"
if echo "$LOGIN_HTML" | grep -q "SkyGuard Admin"; then
    FOUND_TITLE="true"
fi

# The index title appears on the dashboard (app list) page
FOUND_INDEX_TITLE="false"
if echo "$ADMIN_HTML" | grep -q "Fleet Command Center"; then
    FOUND_INDEX_TITLE="true"
fi

# Also check if it appears on the login page (sometimes index title is used in breadcrumbs or headers)
if [ "$FOUND_INDEX_TITLE" = "false" ]; then
    if echo "$LOGIN_HTML" | grep -q "Fleet Command Center"; then
        FOUND_INDEX_TITLE="true"
    fi
fi

# 6. Check file modification (Anti-gaming / Forensic)
# We expect modifications in /opt/aerobridge/aerobridge/urls.py or admin.py
URLS_FILE="/opt/aerobridge/aerobridge/urls.py"
FILE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$URLS_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$URLS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "server_running": $SERVER_RUNNING,
    "http_status": "$LOGIN_HTTP_CODE",
    "found_header": $FOUND_HEADER,
    "found_title": $FOUND_TITLE,
    "found_index_title": $FOUND_INDEX_TITLE,
    "file_modified": $FILE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="