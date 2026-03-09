#!/bin/bash
echo "=== Exporting discontinue_medication results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Verification Data from CouchDB
# We need to find the medication order for Maria Santos and check its status.
# We look for the specific ID we seeded: medication_p1_mariasantos_amox

echo "Querying CouchDB for medication record..."
# Fetch the specific document
DOC_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/medication_p1_mariasantos_amox")

# Also fetch all docs to check if a NEW document was created instead of updating the old one
# (Some workflows might create a new 'stop' order vs updating the status)
ALL_MEDS_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
meds = []
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    # Check if related to Maria Santos (patient_p1_mariasantos)
    patient_ref = d.get('patient', '')
    if 'mariasantos' in patient_ref or 'Maria' in str(d):
        if 'Amoxicillin' in str(d):
            meds.append(doc)
print(json.dumps(meds))
")

# 3. Create Result JSON
# We include the specific doc, plus list of all related meds for the verifier to analyze logic
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_medication_doc": $DOC_JSON,
    "related_medication_docs": $ALL_MEDS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"