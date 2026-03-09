#!/bin/bash
set -e
echo "=== Setting up upload_referral_letter task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure HospitalRun is ready
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Create the patient "Hiroshi Tanaka" (ID: P00555)
# We use a raw CouchDB PUT to ensure the patient exists exactly as expected.
# Note: HospitalRun expects 'data' wrapper for the actual content.
echo "Seeding patient Hiroshi Tanaka..."
PATIENT_ID="patient_p1_00555"
PATIENT_DOC='{
  "firstName": "Hiroshi",
  "lastName": "Tanaka",
  "sex": "Male",
  "dateOfBirth": "1980-05-12T00:00:00.000Z",
  "address": "456 Cherry Blossom Lane",
  "phone": "555-0199",
  "email": "hiroshi.tanaka@example.com",
  "patientId": "P00555",
  "type": "patient",
  "data": {
    "firstName": "Hiroshi",
    "lastName": "Tanaka",
    "sex": "Male",
    "dateOfBirth": "1980-05-12T00:00:00.000Z",
    "address": "456 Cherry Blossom Lane",
    "phone": "555-0199",
    "email": "hiroshi.tanaka@example.com",
    "patientId": "P00555",
    "type": "patient"
  }
}'

# Check if exists, if not create
EXISTING_REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))" 2>/dev/null || echo "")

if [ -z "$EXISTING_REV" ]; then
    hr_couch_put "$PATIENT_ID" "$PATIENT_DOC"
    echo "Patient created."
else
    echo "Patient already exists."
fi

# 3. Create the dummy PDF file
echo "Creating referral letter PDF..."
mkdir -p /home/ga/Documents
PDF_PATH="/home/ga/Documents/referral_letter.pdf"

# Use ImageMagick to create a PDF from text if available, else a dummy file
if command -v convert >/dev/null 2>&1; then
    echo "Referral Letter for Hiroshi Tanaka" > /tmp/letter_content.txt
    echo "Date: $(date)" >> /tmp/letter_content.txt
    echo "Please evaluate patient for neurology consult." >> /tmp/letter_content.txt
    convert /tmp/letter_content.txt "$PDF_PATH" || echo "ImageMagick convert failed, using fallback"
else
    # Fallback: create a text file but name it .pdf (HospitalRun might check extension, browser might not care for upload)
    # Better to try python if installed
    python3 -c "f=open('$PDF_PATH','wb'); f.write(b'%PDF-1.0\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 3 3]>>endobj\nxref\n0 4\n0000000000 65535 f\n0000000010 00000 n\n0000000060 00000 n\n0000000117 00000 n\ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n173\n%%EOF\n')" || echo "Dummy PDF generation failed"
fi

# Ensure permissions
chown ga:ga "$PDF_PATH"
chmod 644 "$PDF_PATH"

# 4. Prepare Browser
ensure_hospitalrun_logged_in
wait_for_db_ready

# Navigate to patients list initially
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# 5. Capture Initial State
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="