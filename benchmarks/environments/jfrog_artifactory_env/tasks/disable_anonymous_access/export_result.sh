#!/bin/bash
set -e
echo "=== Exporting task results: disable_anonymous_access ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check System Configuration (Programmatic Check)
#    We query the system config and look for anonAccessEnabled
CONFIG_CONTENT=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "${ARTIFACTORY_URL}/artifactory/api/system/configuration" 2>/dev/null)

# Check if anonAccessEnabled is false in the XML/YAML output
IS_ANON_ENABLED_IN_CONFIG="unknown"
if echo "$CONFIG_CONTENT" | grep -qi "anonAccessEnabled.*false"; then
    IS_ANON_ENABLED_IN_CONFIG="false"
elif echo "$CONFIG_CONTENT" | grep -qi "anonAccessEnabled.*true"; then
    IS_ANON_ENABLED_IN_CONFIG="true"
fi

# 3. Behavioral Check: Attempt unauthenticated access
#    Should return 401 (Unauthorized) or 403 (Forbidden) if disabled
FINAL_ANON_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${ARTIFACTORY_URL}/artifactory/api/repositories" 2>/dev/null)

# 4. Sanity Check: Attempt authenticated access
#    Should return 200 (OK) - ensure agent didn't break the system
FINAL_AUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "${ARTIFACTORY_URL}/artifactory/api/repositories" 2>/dev/null)

# 5. Get initial state for comparison
INITIAL_ANON_STATUS=$(cat /tmp/initial_anon_state.txt 2>/dev/null || echo "0")

# 6. Construct JSON Result
#    Using a temp file to avoid permission issues, then moving
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_anon_enabled": "$IS_ANON_ENABLED_IN_CONFIG",
    "final_anon_status": $FINAL_ANON_STATUS,
    "final_auth_status": $FINAL_AUTH_STATUS,
    "initial_anon_status": $INITIAL_ANON_STATUS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json