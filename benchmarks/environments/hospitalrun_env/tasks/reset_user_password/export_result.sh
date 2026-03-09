#!/bin/bash
echo "=== Exporting reset_user_password result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Functional Verification: Attempt Login with NEW password
# We test against CouchDB _session endpoint directly
echo "Testing authentication for dr_amani..."
AUTH_RESPONSE=$(curl -s -X POST "http://localhost:5984/_session" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "name=dr_amani&password=WelcomeBack2026!")

# Check if auth succeeded ("ok":true)
AUTH_SUCCESS="false"
if echo "$AUTH_RESPONSE" | grep -q '"ok":true'; then
    AUTH_SUCCESS="true"
    echo "Authentication successful!"
else
    echo "Authentication failed. Response: $AUTH_RESPONSE"
fi

# 3. Data Integrity Check: Fetch the user document
echo "Fetching final user document..."
curl -s "http://couchadmin:test@localhost:5984/_users/org.couchdb.user:dr_amani" > /tmp/final_user_doc.json

# 4. Compare Revisions (Anti-Gaming)
INITIAL_REV=$(python3 -c "import json; print(json.load(open('/tmp/initial_target_user.json')).get('_rev', ''))" 2>/dev/null || echo "0")
FINAL_REV=$(python3 -c "import json; print(json.load(open('/tmp/final_user_doc.json')).get('_rev', ''))" 2>/dev/null || echo "0")

DOC_MODIFIED="false"
if [ "$INITIAL_REV" != "$FINAL_REV" ] && [ -n "$FINAL_REV" ]; then
    DOC_MODIFIED="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "auth_success": $AUTH_SUCCESS,
    "doc_modified": $DOC_MODIFIED,
    "initial_rev": "$INITIAL_REV",
    "final_rev": "$FINAL_REV",
    "final_doc_path": "/tmp/final_user_doc.json",
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"