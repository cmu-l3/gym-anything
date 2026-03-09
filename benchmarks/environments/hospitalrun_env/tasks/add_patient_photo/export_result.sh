#!/bin/bash
echo "=== Exporting add_patient_photo results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query CouchDB for photos linked to Dolores Welch
PATIENT_ID="patient_p1_dolores"
echo "Querying CouchDB for photos..."

# We fetch all docs and filter in Python for robustness
# We are looking for docs created/modified AFTER task start
# that are linked to our patient.
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

# Extract relevant photo documents using Python
python3 -c "
import sys, json, time

task_start = int($TASK_START)
patient_id = '$PATIENT_ID'

try:
    with open('/tmp/all_docs.json') as f:
        data = json.load(f)
except Exception:
    data = {'rows': []}

photos_found = []

for row in data.get('rows', []):
    doc = row.get('doc', {})
    # Handle HospitalRun's data wrapper if present
    d = doc.get('data', doc)
    
    # Check linkage to patient
    p_ref = d.get('patient', '')
    # Also check name if ID ref is missing (fallback)
    is_linked = (patient_id in p_ref) or ('Dolores' in str(d) and 'Welch' in str(d))
    
    # Check if it looks like a photo
    # HospitalRun photo docs usually have type='photo' or are attachments
    is_photo = (d.get('type') == 'photo') or ('photo' in doc.get('_id', '')) or ('image' in d.get('fileType', ''))
    
    if is_linked and is_photo:
        # Check basic fields
        desc = d.get('description', '')
        
        # Check attachments/files
        has_file = False
        if '_attachments' in doc:
            has_file = True
        elif d.get('file') or d.get('files'):
            has_file = True
            
        photos_found.append({
            'id': doc.get('_id'),
            'rev': doc.get('_rev'),
            'description': desc,
            'has_file': has_file,
            'doc_dump': str(d)
        })

# Save found photos to JSON
with open('/tmp/found_photos.json', 'w') as f:
    json.dump(photos_found, f)
"

# 4. Get counts
INITIAL_COUNT=$(cat /tmp/initial_photo_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(jq '. | length' /tmp/found_photos.json 2>/dev/null || echo "0")

# 5. Check if application was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "photos": $(cat /tmp/found_photos.json),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json