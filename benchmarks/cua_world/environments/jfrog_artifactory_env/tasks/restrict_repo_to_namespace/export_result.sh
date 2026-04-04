#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Verification Variables
REPO_KEY="example-repo-local"
VALID_PATH="com/acme/verification-ok.txt"
INVALID_PATH="org/rogue/verification-fail.txt"
TEST_CONTENT="verification-content-$(date +%s)"

echo "Starting verification for $REPO_KEY..."

# ---------------------------------------------------------
# CHECK 1: CONFIGURATION (API)
# Try to get repo config to check includesPattern directly
# ---------------------------------------------------------
# Note: In some OSS versions, GET /api/repositories/{key} is restricted.
# We attempt it, but degrade gracefully to functional testing if it fails.
CONFIG_JSON=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/repositories/${REPO_KEY}")
INCLUDES_PATTERN=$(echo "$CONFIG_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('includesPattern', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

echo "Detected Includes Pattern: $INCLUDES_PATTERN"

# ---------------------------------------------------------
# CHECK 2: POSITIVE BEHAVIORAL TEST
# Upload should SUCCEED (HTTP 201)
# ---------------------------------------------------------
echo "Attempting upload to allowed path: $VALID_PATH"
HTTP_CODE_VALID=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT \
    -H "Content-Type: text/plain" \
    -d "$TEST_CONTENT" \
    "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${VALID_PATH}")

echo "Upload Allowed Path Result: $HTTP_CODE_VALID"

# ---------------------------------------------------------
# CHECK 3: NEGATIVE BEHAVIORAL TEST
# Upload should FAIL (HTTP 403 or 409 or 404 depending on impl, usually 409/403 for restricted path)
# ---------------------------------------------------------
echo "Attempting upload to restricted path: $INVALID_PATH"
HTTP_CODE_INVALID=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT \
    -H "Content-Type: text/plain" \
    -d "$TEST_CONTENT" \
    "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${INVALID_PATH}")

echo "Upload Restricted Path Result: $HTTP_CODE_INVALID"

# ---------------------------------------------------------
# EXPORT JSON
# ---------------------------------------------------------
# Determine if checks passed based on HTTP codes
# Valid upload: 201 Created
# Invalid upload: 409 Conflict (Forbidden path) or 403 Forbidden
POSITIVE_TEST_PASSED="false"
if [ "$HTTP_CODE_VALID" == "201" ]; then
    POSITIVE_TEST_PASSED="true"
fi

NEGATIVE_TEST_PASSED="false"
if [ "$HTTP_CODE_INVALID" == "409" ] || [ "$HTTP_CODE_INVALID" == "403" ]; then
    NEGATIVE_TEST_PASSED="true"
fi

CONFIG_MATCH="false"
if [ "$INCLUDES_PATTERN" == "com/acme/**" ]; then
    CONFIG_MATCH="true"
fi

# Cleanup verification artifacts
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X DELETE "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/${VALID_PATH}" >/dev/null 2>&1 || true

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_includes_pattern": "$INCLUDES_PATTERN",
    "config_match": $CONFIG_MATCH,
    "positive_test_passed": $POSITIVE_TEST_PASSED,
    "positive_test_code": "$HTTP_CODE_VALID",
    "negative_test_passed": $NEGATIVE_TEST_PASSED,
    "negative_test_code": "$HTTP_CODE_INVALID",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Move to final location with wide permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json