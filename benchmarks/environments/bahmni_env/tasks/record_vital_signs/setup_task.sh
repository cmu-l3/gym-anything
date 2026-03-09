#!/bin/bash

echo "=== Setting up record_vital_signs task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Bahmni is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Verify patient BAH000011 (James Osei) exists
PATIENT_UUID=$(get_patient_uuid_by_identifier "BAH000011")
if [ -z "$PATIENT_UUID" ]; then
  echo "ERROR: Patient BAH000011 (James Osei) not found. Was seeding run?"
  ALL_PATIENTS=$(openmrs_api_get "/patient?limit=5&v=default")
  echo "Available patients: $(echo "$ALL_PATIENTS" | jq -r '.results[].display' 2>/dev/null || true)"
  exit 1
fi
log "Found patient BAH000011 (James Osei) with UUID: $PATIENT_UUID"

# Ensure the patient has a pre-existing OPD visit (required for clinical workflow).
# The seed script creates visits for all patients; this check verifies it worked.
VISITS=$(openmrs_api_get "/visit?patient=${PATIENT_UUID}&limit=1&v=default")
VISIT_COUNT=$(echo "$VISITS" | jq -r '.results | length' 2>/dev/null || echo "0")
if [ "$VISIT_COUNT" = "0" ]; then
  log "No existing visit found for James Osei — creating OPD visit..."
  LOCATION_UUID=$(openmrs_api_get "/location?limit=1&v=default" | jq -r '.results[0].uuid // empty' 2>/dev/null || true)
  VISIT_TYPE_UUID=$(openmrs_api_get "/visittype?limit=1&v=default" | jq -r '.results[0].uuid // empty' 2>/dev/null || true)
  if [ -n "$LOCATION_UUID" ] && [ -n "$VISIT_TYPE_UUID" ]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
    openmrs_api_post "/visit" "{\"patient\":\"${PATIENT_UUID}\",\"visitType\":\"${VISIT_TYPE_UUID}\",\"location\":\"${LOCATION_UUID}\",\"startDatetime\":\"${NOW}\",\"stopDatetime\":\"${NOW}\"}" > /dev/null
    log "Created OPD visit for James Osei"
  fi
fi

# Start Epiphany at the Bahmni login page
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "Patient: James Osei (BAH000011, UUID: $PATIENT_UUID)"
echo "=== Task setup complete ==="
