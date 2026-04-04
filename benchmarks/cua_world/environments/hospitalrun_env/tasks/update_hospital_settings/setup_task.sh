#!/bin/bash
echo "=== Setting up update_hospital_settings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 2. Reset Configuration to known initial state
# We need to find the configuration document. In HospitalRun, it's often in the 'main' db
# with type 'configuration' or id 'configuration'.
echo "Resetting hospital configuration..."

# Helper to find config doc
find_config_doc() {
    curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    # Check for likely config document signatures
    if doc.get('_id') == 'configuration' or d.get('type') == 'configuration' or 'hospitalName' in d:
        print(json.dumps(doc))
        break
"
}

CONFIG_DOC=$(find_config_doc)

if [ -n "$CONFIG_DOC" ]; then
    # Update existing doc
    ID=$(echo "$CONFIG_DOC" | jq -r '._id')
    REV=$(echo "$CONFIG_DOC" | jq -r '._rev')
    
    # Construct update payload (preserving other fields, updating name/email)
    # HospitalRun usually wraps data in a 'data' property
    NEW_DOC=$(echo "$CONFIG_DOC" | jq '.data.hospitalName = "City General Hospital" | .data.hospitalEmail = "admin@citygeneral.org"')
    
    # If .data doesn't exist, try top level
    if [ "$(echo "$NEW_DOC" | jq -r '.data')" = "null" ]; then
        NEW_DOC=$(echo "$CONFIG_DOC" | jq '.hospitalName = "City General Hospital" | .hospitalEmail = "admin@citygeneral.org"')
    fi
    
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${ID}" \
        -H "Content-Type: application/json" \
        -d "$NEW_DOC" > /dev/null
    echo "Configuration reset for ID: $ID"
else
    # Create new default configuration if missing
    # Note: The exact structure depends on the app version, but we make a best guess 
    # compatible with the task description's targets.
    echo "No config found, creating default..."
    curl -s -X POST "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}" \
        -H "Content-Type: application/json" \
        -d '{
            "_id": "configuration",
            "type": "configuration",
            "data": {
                "hospitalName": "City General Hospital",
                "hospitalEmail": "admin@citygeneral.org",
                "currency": "USD"
            }
        }' > /dev/null
fi

# 3. Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
# Kill existing firefox to refresh state
pkill -f firefox 2>/dev/null || true
sleep 2

# We use the helper from task_utils to handle login
ensure_hospitalrun_logged_in

# Navigate to Dashboard initially
navigate_firefox_to "http://localhost:3000"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured"

echo "=== Setup complete ==="