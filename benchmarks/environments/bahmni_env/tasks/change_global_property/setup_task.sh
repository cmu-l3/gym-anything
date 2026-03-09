#!/bin/bash
set -e
echo "=== Setting up change_global_property task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni services are running
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni services failed to start"
    exit 1
fi

# 1. Ensure initial state: default_locale = 'en'
echo "Checking initial state of default_locale..."
CURRENT_VAL=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/systemsetting/default_locale?v=full" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('value','unknown'))" 2>/dev/null || echo "unknown")

if [ "$CURRENT_VAL" != "en" ]; then
    echo "Current value is '$CURRENT_VAL'. Resetting to 'en'..."
    # Reset via API
    curl -sk -X POST \
      -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      -H "Content-Type: application/json" \
      -d '{"property": "default_locale", "value": "en"}' \
      "${OPENMRS_API_URL}/systemsetting/default_locale" > /dev/null
    sleep 2
else
    echo "Current value is already 'en'."
fi

# 2. Record initial timestamp of the property (for anti-gaming verification)
# We need to know if the record was modified *during* the task.
echo "Recording initial property timestamp..."
INITIAL_TS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
  "SELECT UNIX_TIMESTAMP(date_changed) FROM global_property WHERE property = 'default_locale'" 2>/dev/null)

# If date_changed is NULL, check date_created, or default to 0
if [ -z "$INITIAL_TS" ] || [ "$INITIAL_TS" = "NULL" ]; then
    INITIAL_TS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e \
      "SELECT UNIX_TIMESTAMP(date_created) FROM global_property WHERE property = 'default_locale'" 2>/dev/null || echo "0")
fi
echo "${INITIAL_TS:-0}" > /tmp/initial_property_ts.txt

# 3. Start Browser at Login Page
# Using restart_browser from task_utils to handle SSL/Process cleanup
if ! restart_browser "${BAHMNI_LOGIN_URL}"; then
    echo "ERROR: Failed to start browser"
    exit 1
fi

# 4. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="