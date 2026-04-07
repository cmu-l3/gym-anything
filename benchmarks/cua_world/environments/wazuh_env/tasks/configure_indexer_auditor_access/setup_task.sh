#!/bin/bash
set -e
echo "=== Setting up configure_indexer_auditor_access task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Indexer Credentials
IDX_URL="https://localhost:9200"
IDX_USER="admin"
IDX_PASS="SecretPassword"
SECURITY_API="${IDX_URL}/_plugins/_security/api"

# Wait for Indexer to be ready
echo "Waiting for Wazuh Indexer..."
for i in {1..30}; do
    if curl -sk -u "${IDX_USER}:${IDX_PASS}" "${IDX_URL}/_cluster/health" | grep -q "status"; then
        echo "Indexer is ready."
        break
    fi
    sleep 2
done

# CLEANUP: Remove target user, role, and mapping if they exist (ensure clean state)
echo "Cleaning up any existing artifacts..."

# Delete user
curl -sk -u "${IDX_USER}:${IDX_PASS}" -X DELETE "${SECURITY_API}/internalusers/compliance_auditor" >/dev/null 2>&1 || true

# Delete role
curl -sk -u "${IDX_USER}:${IDX_PASS}" -X DELETE "${SECURITY_API}/roles/compliance_read_alerts" >/dev/null 2>&1 || true

# Delete role mapping
curl -sk -u "${IDX_USER}:${IDX_PASS}" -X DELETE "${SECURITY_API}/rolesmapping/compliance_read_alerts" >/dev/null 2>&1 || true

# Remove agent output files if they exist
rm -f /home/ga/auditor_user_check.json
rm -f /home/ga/auditor_role_check.json
rm -f /home/ga/auditor_access_test.json

# Ensure Firefox is running and focused (context)
echo "Ensuring Firefox is open..."
ensure_firefox_wazuh "https://localhost/app/wz-home"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="