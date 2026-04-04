#!/bin/bash
set -e
echo "=== Setting up add_patient_photo task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Fix PouchDB offline sync issue to ensure app loads
fix_offline_sync

# 3. Ensure HospitalRun is accessible
echo "Waiting for HospitalRun..."
wait_for_hospitalrun 30

# 4. Create/Verify Patient 'Dolores Welch' exists
# We use a specific ID to make verification easier
echo "Seeding patient Dolores Welch..."
PATIENT_ID="patient_p1_dolores"
PATIENT_DOC='{
  "data": {
    "friendlyId": "P00010",
    "firstName": "Dolores",
    "lastName": "Welch",
    "sex": "Female",
    "dateOfBirth": "1980-05-15",
    "address": "456 Oak Lane",
    "phone": "555-0199",
    "email": "dolores.welch@example.com",
    "patientType": "Outpatient",
    "status": "Active"
  }
}'

# Check if exists, if not create
if curl -s -f "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}" > /dev/null; then
    echo "Patient exists."
else
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}" \
        -H "Content-Type: application/json" \
        -d "$PATIENT_DOC"
    echo "Patient created."
fi

# 5. Create the photo file to be uploaded
echo "Generating patient photo file..."
mkdir -p /home/ga/Documents
# Use ImageMagick to create a realistic-looking placeholder (plasma fractal)
# This ensures it's a valid JPEG and not just an empty file
convert -size 400x500 plasma:fractal -quality 85 /home/ga/Documents/patient_photo.jpg
chmod 644 /home/ga/Documents/patient_photo.jpg

# 6. Record initial photo count for this patient
# HospitalRun photos are documents with type="photo" (or just linked via patient field in older versions)
# We count docs that link to our patient ID and have photo-like fields
echo "Counting initial photos..."
INITIAL_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
target_id = '${PATIENT_ID}'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc) # HospitalRun wraps data
    # Check linkage
    p_ref = d.get('patient', '')
    if target_id in p_ref or 'Dolores' in str(d):
        # Check if it is a photo doc
        if d.get('type') == 'photo' or 'photo' in doc.get('_id', ''):
            count += 1
print(count)
")
echo "$INITIAL_COUNT" > /tmp/initial_photo_count.txt

# 7. Launch Firefox and login
echo "Launching Firefox..."
ensure_hospitalrun_logged_in
focus_firefox

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="