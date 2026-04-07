#!/bin/bash
# post_task: Export results for verification
set -e

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date +%s)

# Path definitions inside container
CONTAINER="${WAZUH_MANAGER_CONTAINER}"
RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
ALERTS_FILE="/var/ossec/logs/alerts/alerts.json"

# Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 1. Export local_rules.xml
echo "Exporting local_rules.xml..."
docker cp "${CONTAINER}:${RULES_FILE}" /tmp/local_rules.xml 2>/dev/null || echo "Failed to copy rules file"

# 2. Export alerts.json (tailing to keep file size manageable, but enough to find recent alerts)
echo "Exporting recent alerts..."
# We grab the last 2000 lines to ensure we catch the alert if it happened
docker exec "${CONTAINER}" tail -n 2000 "${ALERTS_FILE}" > /tmp/alerts.json 2>/dev/null || echo "Failed to copy alerts file"

# 3. Check if Wazuh Manager is running
MANAGER_RUNNING="false"
if docker exec "${CONTAINER}" /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "wazuh-analysisd is running"; then
    MANAGER_RUNNING="true"
fi

# Prepare JSON result
RESULT_JSON="/tmp/task_result.json"

# We construct the JSON carefully
# Note: we are NOT verifying here, just exporting data for the python verifier
# However, we can add some basic file stats
RULES_SIZE=$(stat -c %s /tmp/local_rules.xml 2>/dev/null || echo 0)
ALERTS_SIZE=$(stat -c %s /tmp/alerts.json 2>/dev/null || echo 0)

cat > "${RESULT_JSON}" << EOF
{
    "task_start_timestamp": ${TASK_START},
    "export_timestamp": ${TIMESTAMP},
    "manager_running": ${MANAGER_RUNNING},
    "rules_file_exported": $([ -f /tmp/local_rules.xml ] && echo "true" || echo "false"),
    "alerts_file_exported": $([ -f /tmp/alerts.json ] && echo "true" || echo "false"),
    "rules_file_size": ${RULES_SIZE},
    "alerts_file_size": ${ALERTS_SIZE}
}
EOF

# Ensure permissions
chmod 666 "${RESULT_JSON}" /tmp/local_rules.xml /tmp/alerts.json /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to ${RESULT_JSON}"