#!/bin/bash
echo "=== Exporting Create Inventory Request Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Determine CouchDB URL
COUCH_URL="http://couchadmin:test@localhost:5984"

# Get all documents to analyze in verifier
echo "Fetching all documents from CouchDB..."
ALL_DOCS_FILE="/tmp/all_docs.json"
curl -s "${COUCH_URL}/main/_all_docs?include_docs=true" > "$ALL_DOCS_FILE"

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_inv_request_count.txt 2>/dev/null || echo "0")

# Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON result
# We will embed the full docs list (or a filtered list) to avoid creating massive files,
# but for verification logic ease, we'll let python handle the filtering if the file isn't too huge.
# HospitalRun demo DB is small.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_request_count": $INITIAL_COUNT,
    "screenshot_path": "/tmp/task_final.png",
    "couchdb_dump_path": "$ALL_DOCS_FILE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="