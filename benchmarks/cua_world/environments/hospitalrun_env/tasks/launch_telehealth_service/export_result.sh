#!/bin/bash
echo "=== Exporting launch_telehealth_service results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Fetch Configuration State (Visit Type Lookup)
echo "Fetching configuration state..."
VISIT_TYPE_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_type")

# 2. Fetch Appointments for Lars Jensen
echo "Fetching appointments..."
# Query all docs and filter in python for flexibility
APPOINTMENTS_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
rows = data.get('rows', [])
matches = []
for row in rows:
    doc = row.get('doc', {})
    # Handle HospitalRun data wrapper if present
    d = doc.get('data', doc)
    
    # Check if it's an appointment
    doc_type = d.get('type', doc.get('type', ''))
    
    # Appointments in HR usually have type='appointment' inside data, or the doc id starts with appointment_
    if doc_type == 'appointment' or row['id'].startswith('appointment_'):
        # Check if linked to Lars Jensen
        patient_str = str(d.get('patient', '')).lower()
        title_str = str(d.get('title', '')).lower() # Sometimes title contains name
        
        if 'lars' in patient_str or 'jensen' in patient_str or 'lars' in title_str:
            matches.append(d)

print(json.dumps(matches))
")

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_doc": $VISIT_TYPE_DOC,
    "appointments": $APPOINTMENTS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"