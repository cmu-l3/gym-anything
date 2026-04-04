#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPO="example-repo-local"
PUBLIC_PATH="public/info.txt"
SECRET_PATH="secret/passwords.txt"
ARTIFACTORY_URL="http://localhost:8082"

echo "Testing access controls..."

# ==============================================================================
# TEST 1: Anonymous Access to PUBLIC content
# ==============================================================================
# We use curl WITHOUT '-u' to simulate anonymous user
HTTP_PUBLIC=$(curl -s -o /dev/null -w "%{http_code}" "${ARTIFACTORY_URL}/artifactory/${REPO}/${PUBLIC_PATH}")
echo "Public Access (Anon): HTTP $HTTP_PUBLIC"

# ==============================================================================
# TEST 2: Anonymous Access to SECRET content
# ==============================================================================
HTTP_SECRET=$(curl -s -o /dev/null -w "%{http_code}" "${ARTIFACTORY_URL}/artifactory/${REPO}/${SECRET_PATH}")
echo "Secret Access (Anon): HTTP $HTTP_SECRET"

# ==============================================================================
# TEST 3: Anonymous WRITE Access (Safety Check)
# ==============================================================================
# Try to upload a file as anonymous
echo "hacked" > /tmp/hack.txt
HTTP_WRITE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -T /tmp/hack.txt "${ARTIFACTORY_URL}/artifactory/${REPO}/public/hacked.txt")
echo "Write Access (Anon): HTTP $HTTP_WRITE"
rm -f /tmp/hack.txt

# ==============================================================================
# TEST 4: Global Configuration Check (API)
# ==============================================================================
# Get system configuration to check 'anonAccessEnabled'
CONFIG_XML=$(curl -s -u admin:password "${ARTIFACTORY_URL}/artifactory/api/system/configuration")
ANON_ENABLED=$(echo "$CONFIG_XML" | grep -o "<anonAccessEnabled>true</anonAccessEnabled>" > /dev/null && echo "true" || echo "false")
echo "Global Anon Enabled: $ANON_ENABLED"

# ==============================================================================
# Finalize
# ==============================================================================

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "http_public_read": "$HTTP_PUBLIC",
    "http_secret_read": "$HTTP_SECRET",
    "http_public_write": "$HTTP_WRITE",
    "global_anon_enabled": $ANON_ENABLED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move with permission fix
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="