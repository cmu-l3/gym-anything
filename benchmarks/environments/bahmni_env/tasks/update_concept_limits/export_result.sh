#!/bin/bash
set -u

echo "=== Exporting update_concept_limits results ==="

source /workspace/scripts/task_utils.sh

# Task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Concept UUID for "Weight (kg)"
CONCEPT_UUID="5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

echo "Fetching final concept state from OpenMRS API..."

# Fetch the full concept definition
CONCEPT_JSON=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/concept/${CONCEPT_UUID}?v=full")

# Check if fetch was successful
if [ -z "$CONCEPT_JSON" ] || [ "$(echo "$CONCEPT_JSON" | jq 'has("uuid")')" != "true" ]; then
    echo "ERROR: Failed to retrieve concept data."
    CONCEPT_EXISTS="false"
else
    CONCEPT_EXISTS="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
# We extract specific fields using python/jq to ensure clean types, 
# or just dump the whole concept payload and let the verifier parse it.
# Embedding the whole concept JSON is safer.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "concept_exists": $CONCEPT_EXISTS,
    "concept_data": $CONCEPT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="