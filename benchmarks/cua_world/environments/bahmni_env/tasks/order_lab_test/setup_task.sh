#!/bin/bash
set -e
echo "=== Setting up order_lab_test task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Verify patient exists
PATIENT_ID="BAH000012"
PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_ID")

if [ -z "$PATIENT_UUID" ]; then
  echo "ERROR: Patient $PATIENT_ID (Michael Brown) not found. Was seeding run?"
  exit 1
fi
log "Found patient $PATIENT_ID with UUID: $PATIENT_UUID"

# Record initial order count for this patient (for debugging/verification)
INITIAL_ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=testorder&v=default")
INITIAL_COUNT=$(echo "$INITIAL_ORDERS_JSON" | jq -r '.results | length' 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_order_count.txt
log "Initial test order count for patient: $INITIAL_COUNT"

# Ensure an active visit exists? 
# The task description allows the agent to start one, but pre-creating one reduces friction.
# We will create one if none exists to ensure the "Orders" tab is accessible immediately.
VISITS=$(openmrs_api_get "/visit?patient=${PATIENT_UUID}&includeInactive=false&v=default")
ACTIVE_VISIT_COUNT=$(echo "$VISITS" | jq -r '.results | length' 2>/dev/null || echo "0")

if [ "$ACTIVE_VISIT_COUNT" = "0" ]; then
  log "No active visit found for $PATIENT_ID. Creating new OPD visit..."
  LOCATION_UUID=$(openmrs_api_get "/location?limit=1&v=default" | jq -r '.results[0].uuid // empty' 2>/dev/null || true)
  VISIT_TYPE_UUID=$(openmrs_api_get "/visittype?q=OPD&v=default" | jq -r '.results[0].uuid // empty' 2>/dev/null || true)
  
  if [ -z "$VISIT_TYPE_UUID" ]; then
    # Fallback if OPD specific type not found
    VISIT_TYPE_UUID=$(openmrs_api_get "/visittype?limit=1&v=default" | jq -r '.results[0].uuid // empty' 2>/dev/null || true)
  fi

  if [ -n "$LOCATION_UUID" ] && [ -n "$VISIT_TYPE_UUID" ]; then
    # Start time = now
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
    # Note: No stopDatetime means it's active
    PAYLOAD="{\"patient\":\"${PATIENT_UUID}\",\"visitType\":\"${VISIT_TYPE_UUID}\",\"location\":\"${LOCATION_UUID}\",\"startDatetime\":\"${NOW}\"}"
    openmrs_api_post "/visit" "$PAYLOAD" > /dev/null
    log "Created active OPD visit for $PATIENT_ID"
  else
    log "WARNING: Could not create visit (missing location or visit type). Agent may need to create it."
  fi
else
  log "Active visit already exists for $PATIENT_ID"
fi

# Launch Browser
echo "Launching browser..."
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="