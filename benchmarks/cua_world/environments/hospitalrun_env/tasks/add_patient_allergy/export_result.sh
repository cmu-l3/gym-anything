#!/bin/bash
set -e
echo "=== Exporting add_patient_allergy results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Export all documents from CouchDB 'main' database
# We will filter this in Python to avoid complex Bash logic
echo "Exporting database dump..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/couchdb_dump.json

# 4. Create result JSON
# We include the raw dump path, timestamps, and screenshot path
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "database_dump_path": "/tmp/couchdb_dump.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions so the verifier (running as host user) can read it
chmod 666 /tmp/task_result.json
chmod 666 /tmp/couchdb_dump.json
chmod 666 /tmp/task_final.png

echo "Export complete. Result saved to /tmp/task_result.json"