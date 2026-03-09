#!/bin/bash
echo "=== Exporting Restore Voided Encounter Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_ENC_UUID=$(cat /tmp/target_encounter_uuid.txt 2>/dev/null)

if [ -z "$TARGET_ENC_UUID" ]; then
  echo "ERROR: Target encounter UUID not found from setup"
  # Generate a fail JSON
  cat <<EOF > /tmp/task_result.json
{
  "error": "Setup failed to record target UUID"
}
EOF
  exit 0
fi

# 3. Query OpenMRS for Encounter Status
# We must use includeAll=true to see it if it's still voided, 
# though we expect it to be unvoided now.
ENC_DATA=$(openmrs_api_get "/encounter/${TARGET_ENC_UUID}?includeAll=true&v=full")

# Extract fields
IS_VOIDED=$(echo "$ENC_DATA" | jq -r '.voided')
AUDIT_INFO=$(echo "$ENC_DATA" | jq -r '.auditInfo // empty')
DATE_CHANGED=$(echo "$AUDIT_INFO" | jq -r '.dateChanged // empty')

# 4. Check App State
APP_RUNNING="false"
if pgrep -f "epiphany" >/dev/null; then
  APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat <<EOF > "$TEMP_JSON"
{
  "task_start_timestamp": $TASK_START,
  "target_encounter_uuid": "$TARGET_ENC_UUID",
  "is_voided": $IS_VOIDED,
  "date_changed": "$DATE_CHANGED",
  "app_running": $APP_RUNNING,
  "raw_response_found": $(if [ -n "$ENC_DATA" ]; then echo "true"; else echo "false"; fi)
}
EOF

# Safe copy
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="