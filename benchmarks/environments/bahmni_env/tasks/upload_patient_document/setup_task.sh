#!/bin/bash
echo "=== Setting up upload_patient_document task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
date -u +"%Y-%m-%dT%H:%M:%S.000+0000" > /tmp/task_start_iso.txt

# 1. Create the dummy scanned document
echo "Generating scanned document..."
mkdir -p /home/ga/Documents

# Use ImageMagick to create a realistic-looking "scanned" JPG
if command -v convert >/dev/null 2>&1; then
    convert -size 800x1000 xc:white \
        -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 50,50 'EXTERNAL LABORATORY REPORT'" \
        -draw "text 50,100 'Patient: Maria Gonzalez'" \
        -draw "text 50,150 'DOB: 1972-06-15'" \
        -draw "text 50,250 'Test: HbA1c'" \
        -draw "text 50,300 'Result: 5.8%'" \
        -draw "text 50,350 'Status: Normal'" \
        -draw "text 50,800 'Report Date: $(date +%Y-%m-%d)'" \
        /home/ga/Documents/external_lab_report.jpg
else
    # Fallback if ImageMagick not installed (though it should be)
    echo "External Lab Report for Maria Gonzalez" > /home/ga/Documents/external_lab_report.txt
    # Rename to jpg to match task description even if content is text (browser might treat weirdly but file picker won't care)
    mv /home/ga/Documents/external_lab_report.txt /home/ga/Documents/external_lab_report.jpg
fi

# Set permissions so the agent user can read it
chown ga:ga /home/ga/Documents/external_lab_report.jpg
chmod 644 /home/ga/Documents/external_lab_report.jpg

echo "Created /home/ga/Documents/external_lab_report.jpg"

# 2. Ensure Bahmni is running
if ! wait_for_bahmni 600; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# 3. Get Patient UUID for Maria Gonzalez (BAH000002)
# We need this to record the initial state of observations for this specific patient
PATIENT_UUID=$(get_patient_uuid_by_identifier "BAH000002")
if [ -z "$PATIENT_UUID" ]; then
    echo "WARNING: Patient BAH000002 not found (seeding might have failed or IDs shifted)."
    # Try to find by name
    PATIENT_UUID=$(openmrs_api_get "/patient?q=Maria+Gonzalez&v=default" | jq -r '.results[0].uuid // empty')
fi

if [ -n "$PATIENT_UUID" ]; then
    echo "$PATIENT_UUID" > /tmp/target_patient_uuid.txt
    
    # Record initial observation count for this patient
    INITIAL_OBS=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=default" | jq '.results | length')
    echo "${INITIAL_OBS:-0}" > /tmp/initial_obs_count.txt
    echo "Initial observation count for patient $PATIENT_UUID: ${INITIAL_OBS:-0}"
else
    echo "ERROR: Could not find target patient Maria Gonzalez"
    exit 1
fi

# 4. Start Browser
# Start Firefox at the Bahmni login page
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
sleep 2

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="