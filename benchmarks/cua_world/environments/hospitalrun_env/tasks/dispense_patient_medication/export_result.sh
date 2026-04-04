#!/bin/bash
set -e
echo "=== Exporting dispense_patient_medication results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Fetch Document States
echo "Fetching final document states..."

# Helper to get full doc
get_doc_json() {
    hr_couch_get "$1"
}

# Get the three key documents
TARGET_DOC=$(get_doc_json "medication_target_sven")
CANCELLED_DOC=$(get_doc_json "medication_distractor_sven_cancelled")
OTHER_DOC=$(get_doc_json "medication_distractor_janice")

# 3. Create Result JSON
# We include the full documents to let the python verifier do the logic
cat > /tmp/task_result.json <<EOF
{
  "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
  "task_end_time": $(date +%s),
  "target_doc": $TARGET_DOC,
  "distractor_cancelled_doc": $CANCELLED_DOC,
  "distractor_other_doc": $OTHER_DOC,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"