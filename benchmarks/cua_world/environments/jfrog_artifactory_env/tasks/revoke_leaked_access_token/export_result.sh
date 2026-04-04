#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Revoke Token Result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load saved tokens
if [ -f /tmp/prod_token.txt ]; then
    PROD_TOKEN=$(cat /tmp/prod_token.txt)
else
    PROD_TOKEN=""
fi

if [ -f /tmp/staging_token.txt ]; then
    STAGING_TOKEN=$(cat /tmp/staging_token.txt)
else
    STAGING_TOKEN=""
fi

# ==============================================================================
# Check 1: Is Staging Token (Leaked) Revoked?
# ==============================================================================
# We test this by trying to use the token. 
# HTTP 200 = Active (Fail)
# HTTP 401/403 = Revoked (Pass)
echo "Checking Staging token status..."
STAGING_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${STAGING_TOKEN}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/ping")

echo "Staging Token HTTP Code: $STAGING_HTTP_CODE"

if [ "$STAGING_HTTP_CODE" == "200" ]; then
    LEAKED_REVOKED="false"
else
    # 401 or similar means it's invalid/revoked
    LEAKED_REVOKED="true"
fi

# ==============================================================================
# Check 2: Is Production Token Still Active?
# ==============================================================================
# HTTP 200 = Active (Pass)
# HTTP 401/403 = Revoked (Fail)
echo "Checking Production token status..."
PROD_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${PROD_TOKEN}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/ping")

echo "Production Token HTTP Code: $PROD_HTTP_CODE"

if [ "$PROD_HTTP_CODE" == "200" ]; then
    PRODUCTION_ACTIVE="true"
else
    PRODUCTION_ACTIVE="false"
fi

# ==============================================================================
# Check 3: Timestamps
# ==============================================================================
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "leaked_token_revoked": $LEAKED_REVOKED,
    "production_token_active": $PRODUCTION_ACTIVE,
    "staging_http_code": "$STAGING_HTTP_CODE",
    "production_http_code": "$PROD_HTTP_CODE",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="