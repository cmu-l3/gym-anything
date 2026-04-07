#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting ISM retention policy task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

INDEXER_URL="https://localhost:9200"
CREDS="admin:SecretPassword"

# 1. Get the policy definition
echo "Fetching policy definition..."
POLICY_JSON=$(curl -sk -u "$CREDS" "${INDEXER_URL}/_plugins/_ism/policies/wazuh-alert-retention" 2>/dev/null || echo "{}")

# 2. Get explanation for wazuh-alerts indices (checks attachment)
echo "Fetching policy attachment status..."
EXPLAIN_JSON=$(curl -sk -u "$CREDS" -X POST \
    "${INDEXER_URL}/_plugins/_ism/explain/wazuh-alerts-*" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null || echo "{}")

# 3. Get list of indices (to know what should have been attached)
INDICES_LIST=$(curl -sk -u "$CREDS" "${INDEXER_URL}/_cat/indices/wazuh-alerts-*?format=json" 2>/dev/null || echo "[]")

# 4. Check if dashboard is running (secondary check)
DASHBOARD_RUNNING="false"
if pgrep -f "node" > /dev/null 2>&1; then 
    # OpenSearch Dashboards runs as node
    DASHBOARD_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "policy_definition": $POLICY_JSON,
    "policy_explanation": $EXPLAIN_JSON,
    "indices_list": $INDICES_LIST,
    "dashboard_running": $DASHBOARD_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="