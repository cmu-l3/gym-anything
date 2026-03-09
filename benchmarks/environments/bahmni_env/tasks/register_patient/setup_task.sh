#!/bin/bash

echo "=== Setting up register_patient task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Ensure Bahmni OpenMRS API is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

# Verify login credentials work
LOGIN_RESP=$(curl -skS \
  -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  -H "Content-Type: application/json" \
  "${OPENMRS_API_URL}/session" 2>/dev/null || true)
IS_AUTH=$(echo "$LOGIN_RESP" | jq -r '.authenticated // false' 2>/dev/null || echo "false")

if [ "$IS_AUTH" != "true" ]; then
  echo "ERROR: Admin credentials are not valid"
  exit 1
fi
log "Admin credentials verified"

# Ensure the target patient does NOT already exist (clean state)
EXISTING=$(openmrs_api_get "/patient?q=Kwame+Mensah&v=default")
EXISTING_UUID=$(echo "$EXISTING" | jq -r '.results[0].uuid // empty' 2>/dev/null || true)
if [ -n "$EXISTING_UUID" ]; then
  log "Removing pre-existing Kwame Mensah patient for clean state"
  curl -sS -X DELETE \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/patient/${EXISTING_UUID}?purge=true" 2>/dev/null || true
  sleep 1
fi

# Start Firefox at the Bahmni login page
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
