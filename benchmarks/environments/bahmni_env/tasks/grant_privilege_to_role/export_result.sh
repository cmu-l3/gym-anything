#!/bin/bash
set -e

echo "=== Exporting Grant Privilege task results ==="

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# DATA COLLECTION: Query OpenMRS API for final state
# ------------------------------------------------------------------
echo "Querying final state of 'Midwife' role..."

AUTH="-u ${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}"
API="${OPENMRS_API_URL}"

# Fetch full role details
# We use a temporary file to avoid pipefail issues if curl fails
TEMP_ROLE_FILE=$(mktemp)
curl -sk $AUTH "${API}/role/Midwife?v=full" > "$TEMP_ROLE_FILE" 2>/dev/null || echo "{}" > "$TEMP_ROLE_FILE"

# Check if browser was running
APP_RUNNING="false"
if pgrep -f "epiphany" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
# We embed the raw OpenMRS JSON response into our result object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 -c "
import json
import os
import time

try:
    with open('$TEMP_ROLE_FILE', 'r') as f:
        role_data = json.load(f)
except Exception:
    role_data = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_was_running': $APP_RUNNING,
    'role_data': role_data,
    'screenshot_path': '/tmp/task_final.png'
}

print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Secure copy to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" "$TEMP_ROLE_FILE"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="