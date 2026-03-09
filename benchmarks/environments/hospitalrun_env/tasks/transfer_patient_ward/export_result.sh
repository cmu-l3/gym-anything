#!/bin/bash
set -e
echo "=== Exporting transfer_patient_ward results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data for Verification
# We fetch the specific visit document we are tracking.
echo "Fetching visit document..."
VISIT_DOC=$(hr_couch_get "visit_p1_liwei_001")

# 3. Get Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Create Result JSON
# We include the raw CouchDB document and system timestamps
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "visit_doc": $VISIT_DOC,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"