#!/bin/bash
echo "=== Exporting modify_user_permissions result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REV=$(cat /tmp/initial_user_rev.txt 2>/dev/null || echo "")

# 3. Query the target user document from CouchDB
TARGET_DOC_ID="org.couchdb.user:jmiller"
USERS_DB="_users"

# Fetch the raw JSON document
USER_DOC=$(curl -s "${HR_COUCH_URL}/${USERS_DB}/${TARGET_DOC_ID}")

# Extract relevant fields using Python for safety
PARSED_RESULT=$(echo "$USER_DOC" | python3 -c "
import sys, json
try:
    doc = json.load(sys.stdin)
    print(json.dumps({
        'exists': '_id' in doc,
        'roles': doc.get('roles', []),
        'current_rev': doc.get('_rev', ''),
        'error': doc.get('error', None)
    }))
except Exception as e:
    print(json.dumps({'exists': False, 'error': str(e)}))
")

# 4. Check if we are still on the Users page (optional context)
# We can't easily check the URL from bash without xdotool hacks, so we rely on VLM/screenshots mostly.
# But we can check if the browser is running.
BROWSER_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 5. Compile Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_rev": "$INITIAL_REV",
    "user_doc": $PARSED_RESULT,
    "browser_running": $BROWSER_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="