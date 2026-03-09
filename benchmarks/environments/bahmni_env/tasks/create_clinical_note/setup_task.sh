#!/bin/bash

echo "=== Setting up create_clinical_note task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Bahmni is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Verify patient BAH000003 (Sarah Johnson) exists
PATIENT_UUID=$(get_patient_uuid_by_identifier "BAH000003")
if [ -z "$PATIENT_UUID" ]; then
  echo "ERROR: Patient BAH000003 (Sarah Johnson) not found. Was seeding run?"
  ALL_PATIENTS=$(openmrs_api_get "/patient?limit=5&v=default")
  echo "Available patients: $(echo "$ALL_PATIENTS" | jq -r '.results[].display' 2>/dev/null || true)"
  exit 1
fi
log "Found patient BAH000003 (Sarah Johnson) with UUID: $PATIENT_UUID"

# Start Firefox at the Bahmni login page
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "Patient: Sarah Johnson (BAH000003, UUID: $PATIENT_UUID)"
echo "=== Task setup complete ==="
