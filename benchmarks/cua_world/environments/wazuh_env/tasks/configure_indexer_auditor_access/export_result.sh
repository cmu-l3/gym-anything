#!/bin/bash
echo "=== Exporting configure_indexer_auditor_access results ==="

source /workspace/scripts/task_utils.sh

# Credentials
IDX_URL="https://localhost:9200"
ADMIN_USER="admin"
ADMIN_PASS="SecretPassword"
SECURITY_API="${IDX_URL}/_plugins/_security/api"

TARGET_USER="compliance_auditor"
TARGET_PASS="AuditP@ss2024!"
TARGET_ROLE="compliance_read_alerts"

# File artifacts checks
USER_FILE_EXISTS=$([ -f "/home/ga/auditor_user_check.json" ] && echo "true" || echo "false")
ROLE_FILE_EXISTS=$([ -f "/home/ga/auditor_role_check.json" ] && echo "true" || echo "false")
TEST_FILE_EXISTS=$([ -f "/home/ga/auditor_access_test.json" ] && echo "true" || echo "false")

# 1. Retrieve User Details (Admin Context)
USER_JSON=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" "${SECURITY_API}/internalusers/${TARGET_USER}")

# 2. Retrieve Role Details (Admin Context)
ROLE_JSON=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" "${SECURITY_API}/roles/${TARGET_ROLE}")

# 3. Retrieve Role Mapping Details (Admin Context)
MAPPING_JSON=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" "${SECURITY_API}/rolesmapping/${TARGET_ROLE}")

# 4. Functional Test: Authenticate as new user
# Try to list indices (should fail or be filtered based on perms, but lets try a direct index search)
# Positive Test: Search wazuh-alerts-*
POSITIVE_TEST_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -u "${TARGET_USER}:${TARGET_PASS}" "${IDX_URL}/wazuh-alerts-*/_search?size=1")

# Negative Test: Search security config (should be 403 Forbidden)
NEGATIVE_TEST_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -u "${TARGET_USER}:${TARGET_PASS}" "${IDX_URL}/.opendistro_security/_search?size=1")

# Write Permission Test: Try to write a document (should be 403 Forbidden)
WRITE_TEST_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"test":"data"}' -u "${TARGET_USER}:${TARGET_PASS}" "${IDX_URL}/wazuh-alerts-test/_doc/")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_artifacts": {
        "user_check_exists": $USER_FILE_EXISTS,
        "role_check_exists": $ROLE_FILE_EXISTS,
        "access_test_exists": $TEST_FILE_EXISTS
    },
    "api_state": {
        "user": $USER_JSON,
        "role": $ROLE_JSON,
        "mapping": $MAPPING_JSON
    },
    "functional_tests": {
        "positive_search_code": $POSITIVE_TEST_CODE,
        "negative_search_code": $NEGATIVE_TEST_CODE,
        "write_test_code": $WRITE_TEST_CODE
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"