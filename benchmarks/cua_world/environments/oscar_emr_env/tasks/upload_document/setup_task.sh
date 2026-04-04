#!/bin/bash
# Setup script for Upload Document task in OSCAR EMR

echo "=== Setting up Upload Document Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Patient "Martha Thompson" exists
FNAME="Martha"
LNAME="Thompson"
DOB="1958-07-22"

echo "Checking for patient $FNAME $LNAME..."
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$FNAME' AND last_name='$LNAME'" || echo "0")

if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "Patient not found. Seeding Martha Thompson..."
    # Insert patient
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('$LNAME', '$FNAME', 'F', '1958', '07', '22', 'Toronto', 'ON', 'M4C 1B5', '416-555-0199', '999998', '5552233441', 'ON', 'AC', NOW());" 2>/dev/null || true
fi

# Get Demographic No
DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$FNAME' AND last_name='$LNAME' LIMIT 1")
echo "Patient Demographic No: $DEMO_NO"
echo "$DEMO_NO" > /tmp/task_patient_no

# 2. Prepare the PDF Document
DOC_DIR="/home/ga/Documents/incoming"
mkdir -p "$DOC_DIR"
DOC_PATH="$DOC_DIR/cardiology_consult_thompson.pdf"

echo "Generating consultation PDF..."
# Create a simple PDF using ImageMagick (convert)
# We create a text file first, then convert it
cat > /tmp/consult_content.txt << EOF
CARDIOLOGY CONSULTATION REPORT
------------------------------
Date: Jan 15, 2024
Patient: Martha Thompson (DOB: 1958-07-22)
Referring Dr: Dr. Sarah Chen
Consultant: Dr. Raj Patel, MD, FRCPC

REASON FOR REFERRAL:
Evaluation of palpitations and occasional chest discomfort.

HISTORY:
Ms. Thompson presents with a 2-month history of intermittent palpitations.
Episodes last 5-10 minutes. No syncope.

EXAMINATION:
BP: 130/80 mmHg, HR: 72 bpm, Regular.
JVP normal. No carotid bruits.
Heart sounds: S1, S2 normal. No murmurs.
Lungs: Clear.

IMPRESSION:
Likely benign palpitations. Holter monitor ordered.

PLAN:
1. 48-hour Holter monitor.
2. Echocardiogram.
3. Follow up in 4 weeks.

Sincerely,
Dr. R. Patel
EOF

# Convert text to PDF using enscript or imagemagick if available, else simple text rename (OSCAR accepts most)
# Using convert from ImageMagick (installed in base)
convert -size 612x792 xc:white -font Courier -pointsize 12 -fill black -annotate +50+50 "@//tmp/consult_content.txt" "$DOC_PATH" 2>/dev/null || \
    cp /tmp/consult_content.txt "$DOC_PATH" # Fallback if convert fails

chmod 644 "$DOC_PATH"
chown ga:ga "$DOC_PATH"
echo "Document prepared at: $DOC_PATH"

# 3. Record Initial State (Anti-Gaming)
# Count documents currently linked to this patient
INITIAL_DOC_COUNT=$(oscar_query "SELECT COUNT(*) FROM ctl_document WHERE module='demographic' AND module_id='$DEMO_NO'" || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_doc_count
echo "Initial document count for patient: $INITIAL_DOC_COUNT"

# Timestamp
date +%s > /tmp/task_start_timestamp

# 4. Launch Firefox
ensure_firefox_on_oscar

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Patient: Martha Thompson"
echo "Document to upload: $DOC_PATH"
echo "Login: oscardoc / oscar / PIN: 1117"