#!/bin/bash
echo "=== Exporting create_user_account result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/create_user_final.png

# 2. Get verification data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Query CouchDB _users database for the new user
# We look for a user where displayName is Maria Santos OR email is maria.santos@hospital.org
echo "Querying CouchDB for new user..."
USER_DATA=$(curl -s "http://couchadmin:test@localhost:5984/_users/_all_docs?include_docs=true" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
found = None
count = 0
for row in data.get('rows', []):
    count += 1
    doc = row.get('doc', {})
    # Check for match
    d_name = doc.get('displayName', '')
    email = doc.get('email', '')
    name = doc.get('name', '')
    
    # Match criteria
    if 'Maria Santos' in d_name or 'maria.santos@hospital.org' in email:
        found = doc
        
print(json.dumps({
    'found': found is not None,
    'user_doc': found,
    'total_users': count
}))
" 2>/dev/null)

# 4. Check if app is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "app_running": $APP_RUNNING,
    "initial_user_count": $INITIAL_COUNT,
    "couchdb_result": $USER_DATA,
    "screenshot_path": "/tmp/create_user_final.png"
}
EOF

# 6. Save result to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="