#!/bin/bash
echo "=== Exporting configure_role_inheritance results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# API details
API_URL="${OPENMRS_API_URL}/role"
AUTH="-u ${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}"

echo "Fetching final state of 'Trainee' role..."
# Fetch full details of the Trainee role to check inheritance
ROLE_JSON=$(curl -sk $AUTH "${API_URL}/Trainee?v=full" 2>/dev/null || echo "{}")

# Check if role exists
ROLE_EXISTS="false"
if echo "$ROLE_JSON" | grep -q '"uuid"'; then
    ROLE_EXISTS="true"
fi

# Check for inheritance of "Provider"
# We parse the JSON to find "Provider" in the inheritedRoles list
INHERITS_PROVIDER="false"
if [ "$ROLE_EXISTS" = "true" ]; then
    INHERITS_PROVIDER=$(echo "$ROLE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    inherited = data.get('inheritedRoles', [])
    # Check by name or display
    found = any(r.get('name') == 'Provider' or r.get('display') == 'Provider' for r in inherited)
    print('true' if found else 'false')
except:
    print('false')
")
fi

# Check if any manual privileges were added (to detect if they just added privileges instead of inheriting)
PRIVILEGE_COUNT="0"
if [ "$ROLE_EXISTS" = "true" ]; then
    PRIVILEGE_COUNT=$(echo "$ROLE_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('privileges', [])))" 2>/dev/null || echo "0")
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "role_exists": $ROLE_EXISTS,
    "inherits_provider": $INHERITS_PROVIDER,
    "direct_privilege_count": $PRIVILEGE_COUNT,
    "role_data": $ROLE_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="