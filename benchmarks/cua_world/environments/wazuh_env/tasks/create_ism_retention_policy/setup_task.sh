#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up ISM retention policy task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh services are running
echo "Checking Wazuh indexer health..."
wait_for_service "Wazuh Indexer" \
    "curl -sk -u admin:SecretPassword https://localhost:9200/_cluster/health | grep -qE '\"status\":\"(green|yellow)\"'" \
    120

# Ensure at least one wazuh-alerts index exists
echo "Checking for existing wazuh-alerts indices..."
ALERT_INDICES=$(curl -sk -u admin:SecretPassword \
    "https://localhost:9200/_cat/indices/wazuh-alerts-*?h=index" 2>/dev/null | head -5)

if [ -z "$ALERT_INDICES" ]; then
    echo "No wazuh-alerts indices found. Creating a sample index manually..."
    # Create a manual index that matches the pattern to ensure the task is performable
    curl -sk -u admin:SecretPassword -X PUT \
        "https://localhost:9200/wazuh-alerts-4.x-2024.01.15" \
        -H "Content-Type: application/json" \
        -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' || true
    sleep 3
fi

# Remove any pre-existing ISM policy with this name (clean state)
echo "Ensuring no pre-existing ISM policy..."
curl -sk -u admin:SecretPassword -X DELETE \
    "https://localhost:9200/_plugins/_ism/policies/wazuh-alert-retention" 2>/dev/null || true

# Remove any ISM policy attachment from existing indices
# This ensures the agent must actively attach the policy
for idx in $(curl -sk -u admin:SecretPassword "https://localhost:9200/_cat/indices/wazuh-alerts-*?h=index" 2>/dev/null); do
    curl -sk -u admin:SecretPassword -X POST \
        "https://localhost:9200/_plugins/_ism/remove/${idx}" \
        -H "Content-Type: application/json" \
        -d '{}' 2>/dev/null || true
done

# Take initial screenshot of dashboard (just to show environment is up)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== ISM retention policy task setup complete ==="