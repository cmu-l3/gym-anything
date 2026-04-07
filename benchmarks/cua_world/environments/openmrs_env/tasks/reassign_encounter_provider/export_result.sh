#!/bin/bash
echo "=== Exporting reassign_encounter_provider results ==="
source /workspace/scripts/task_utils.sh

# Load context
CONTEXT_FILE="/tmp/reassign_provider_context.json"
if [ ! -f "$CONTEXT_FILE" ]; then
    echo "ERROR: Context file not found!"
    exit 1
fi

TARGET_ENC_UUID=$(jq -r '.target_encounter_uuid' "$CONTEXT_FILE")
CORRECT_PROV_UUID=$(jq -r '.correct_provider_uuid' "$CONTEXT_FILE")
BAD_PROV_UUID=$(jq -r '.bad_provider_uuid' "$CONTEXT_FILE")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Fetch current state of the encounter
echo "Fetching encounter $TARGET_ENC_UUID..."
ENC_JSON=$(omrs_get "/encounter/${TARGET_ENC_UUID}?v=full")

# Extract Provider Information
# encounterProviders is a list. We need to check if the correct provider is in it.
# We also check the 'auditInfo' or 'dateChanged' to ensure it was modified recently.

CURRENT_PROVIDERS=$(echo "$ENC_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    providers = []
    for ep in data.get('encounterProviders', []):
        p_uuid = ep.get('provider', {}).get('uuid')
        p_name = ep.get('provider', {}).get('person', {}).get('display')
        if not p_uuid: # Handle sparse objects
            p_uuid = ep.get('provider')
        providers.append({'uuid': p_uuid, 'name': p_name})
    print(json.dumps(providers))
except Exception:
    print('[]')
")

# Check timestamps to verify work was done during task
# "dateChanged" might be on the encounter or the encounterProvider depending on implementation
# We'll check the top-level encounter dateChanged/dateCreated
ENC_TIMESTAMPS=$(echo "$ENC_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    dc = data.get('dateChanged')
    print(json.dumps({'dateChanged': dc}))
except Exception:
    print('{}')
")

# Final Screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start_timestamp": $TASK_START,
    "target_encounter_uuid": "$TARGET_ENC_UUID",
    "expected_provider_uuid": "$CORRECT_PROV_UUID",
    "bad_provider_uuid": "$BAD_PROV_UUID",
    "current_providers": $CURRENT_PROVIDERS,
    "encounter_timestamps": $ENC_TIMESTAMPS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json