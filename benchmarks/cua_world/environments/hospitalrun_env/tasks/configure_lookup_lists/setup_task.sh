#!/bin/bash
echo "=== Setting up configure_lookup_lists task ==="

source /workspace/scripts/task_utils.sh

# 1. Basic Environment Setup
# Fix PouchDB loading issue (CRITICAL for HospitalRun)
fix_offline_sync

# Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Idempotency: Clean up previous run data
echo "Cleaning up any existing target lookup values..."
TARGET_STRINGS=("Orthopedic Consultation" "Orthopedics Wing B" "Dr. Sarah Mitchell")

# Get all docs
ALL_DOCS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true")

# Iterate and delete matching docs
for target in "${TARGET_STRINGS[@]}"; do
    echo "Scanning for existing '$target'..."
    # Python script to find ID and Rev of docs containing the target string
    echo "$ALL_DOCS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
target = \"$target\".lower()
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_str = json.dumps(doc).lower()
    if target in doc_str:
        print(f\"{doc['_id']} {doc['_rev']}\")
" | while read -r doc_id rev; do
        if [ -n "$doc_id" ]; then
            echo "Deleting existing doc: $doc_id"
            curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null
        fi
    done
done

# 3. Capture Initial State (for Anti-Gaming)
echo "Recording initial database state..."
# Save list of all document IDs currently in DB
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs" | \
    python3 -c "import sys, json; print('\n'.join([r['id'] for r in json.load(sys.stdin).get('rows', [])]))" \
    > /tmp/initial_doc_ids.txt

# Record start time
date +%s > /tmp/task_start_time.txt

# 4. Browser Setup
echo "Ensuring Firefox is ready..."
# Kill any stale Firefox
pkill -f firefox 2>/dev/null || true
sleep 1

# Start Firefox and Login
# (Using task_utils.sh helper which handles login loop)
ensure_hospitalrun_logged_in

# Navigate specifically to Dashboard to start
navigate_firefox_to "http://localhost:3000/"
wait_for_db_ready

# Capture initial screenshot
take_screenshot /tmp/lookup_lists_initial.png

echo "=== Setup complete ==="
echo "Agent is at Dashboard. Ready to navigate to Administration."