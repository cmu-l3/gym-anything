#!/bin/bash
echo "=== Exporting configure_lookup_lists result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/lookup_lists_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_VISIT_TYPE="Orthopedic Consultation"
TARGET_LOCATION="Orthopedics Wing B"
TARGET_PHYSICIAN="Dr. Sarah Mitchell"

# 3. Query Database for Results
echo "Querying CouchDB for target values..."
ALL_DOCS_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true")

# Helper to check for a string in new docs
# We check if the doc ID existed before task start (using /tmp/initial_doc_ids.txt)
# Returns JSON object with details
check_value() {
    local target="$1"
    local category="$2"
    
    echo "$ALL_DOCS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
target = \"$target\".lower()
category = \"$category\"

found = False
doc_id = None
is_new = False

# Load initial IDs
try:
    with open('/tmp/initial_doc_ids.txt', 'r') as f:
        initial_ids = set(line.strip() for line in f)
except:
    initial_ids = set()

for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id_curr = row.get('id', '')
    
    # Skip design docs
    if doc_id_curr.startswith('_design'):
        continue
        
    # Search for target value in doc
    doc_str = json.dumps(doc).lower()
    if target in doc_str:
        found = True
        doc_id = doc_id_curr
        # Check if it is a new doc
        if doc_id not in initial_ids:
            is_new = True
        break

print(json.dumps({
    'category': category,
    'found': found,
    'doc_id': doc_id,
    'is_new': is_new,
    'target': \"$target\"
}))
"
}

# Check all three targets
RESULT_VISIT_TYPE=$(check_value "$TARGET_VISIT_TYPE" "Visit Type")
RESULT_LOCATION=$(check_value "$TARGET_LOCATION" "Location")
RESULT_PHYSICIAN=$(check_value "$TARGET_PHYSICIAN" "Physician")

# 4. Generate Output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "results": {
        "visit_type": $RESULT_VISIT_TYPE,
        "location": $RESULT_LOCATION,
        "physician": $RESULT_PHYSICIAN
    },
    "screenshot_path": "/tmp/lookup_lists_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="