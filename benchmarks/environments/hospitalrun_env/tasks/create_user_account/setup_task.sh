#!/bin/bash
echo "=== Setting up create_user_account task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun services are running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 2. Record initial user count in _users database
# The _users DB requires admin credentials
echo "Recording initial user count..."
INITIAL_USERS=$(curl -s "http://couchadmin:test@localhost:5984/_users/_all_docs" | \
    python3 -c "import sys, json; print(len(json.load(sys.stdin).get('rows', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_USERS" > /tmp/initial_user_count.txt
echo "Initial user count: $INITIAL_USERS"

# 3. Clean up any previous attempts (idempotency)
# Check if maria.santos exists and delete if found
echo "Checking for existing Maria Santos user..."
EXISTING_DOC=$(curl -s "http://couchadmin:test@localhost:5984/_users/_all_docs?include_docs=true" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    if 'maria.santos' in doc.get('name', '') or 'Maria Santos' in doc.get('displayName', ''):
        print(doc.get('_id') + '|' + doc.get('_rev'))
" 2>/dev/null || echo "")

if [ -n "$EXISTING_DOC" ]; then
    DOC_ID=$(echo "$EXISTING_DOC" | cut -d'|' -f1)
    REV=$(echo "$EXISTING_DOC" | cut -d'|' -f2)
    echo "Removing existing user: $DOC_ID"
    curl -s -X DELETE "http://couchadmin:test@localhost:5984/_users/${DOC_ID}?rev=${REV}" > /dev/null
fi

# 4. Apply offline sync fix and PouchDB patches
# This is critical for HospitalRun v1 to work correctly in this env
fix_offline_sync

# 5. Launch Firefox and login as admin
# The helper function ensure_hospitalrun_logged_in handles:
# - Killing stale Firefox
# - Opening URL
# - Logging in as hradmin/test if needed
# - Waiting for Dashboard
echo "Launching/Verifying HospitalRun session..."
ensure_hospitalrun_logged_in

# 6. Wait for UI to be stable
sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/create_user_initial.png
echo "Initial state screenshot captured."

echo "=== Task setup complete ==="