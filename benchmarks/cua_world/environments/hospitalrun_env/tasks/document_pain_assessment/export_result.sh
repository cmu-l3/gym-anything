#!/bin/bash
echo "=== Exporting document_pain_assessment results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract data from CouchDB
# We are looking for a document that:
# - Is linked to Lars Jensen (patient_p1_000100)
# - Has the custom form fields (painScore, location, etc.)
# Usually, custom form data in HospitalRun is saved either embedded in the visit OR 
# as a separate document linked to the visit. We will dump all docs and let Python filter.

# Dump all docs (filtered by relevant IDs or types if possible, but _all_docs is safest)
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/couch_dump.json

# 3. Get timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Create result JSON
# We'll do the heavy lifting in Python verifier, just pass the raw dump
# But to be safe with file sizes, let's try to pre-filter in python here if we can,
# or just save the dump. The dump for HospitalRun is usually small (<10MB).
# We'll save the dump to a temp file and let the framework copy it.

cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "screenshot_path": "/tmp/task_final.png",
  "couch_dump_path": "/tmp/couch_dump.json"
}
EOF

echo "Result JSON created at /tmp/task_result.json"