#!/bin/bash
# Setup script for create_index_template task
set -e

echo "=== Setting up create_index_template task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh Indexer is up
echo "Checking Wazuh Indexer health..."
if ! check_indexer_health; then
    echo "Waiting for Indexer..."
    sleep 10
fi

# Clean up existing template if it exists (ensure clean state)
TEMPLATE_NAME="wazuh-custom-alerts"
echo "Cleaning up any existing template '$TEMPLATE_NAME'..."
if wazuh_indexer_query "/_index_template/$TEMPLATE_NAME" | grep -q "$TEMPLATE_NAME"; then
    curl -sk -X DELETE "${WAZUH_INDEXER_URL}/_index_template/$TEMPLATE_NAME" \
        -u "${WAZUH_INDEXER_USER}:${WAZUH_INDEXER_PASS}"
    echo "Deleted existing template."
fi

# Remove output file from previous runs
rm -f /home/ga/index_template_result.json

# Record initial templates list for debugging
wazuh_indexer_query "/_cat/templates?v" > /tmp/initial_templates.txt

# Start Firefox with a blank tab or dashboard (agent can choose tool)
# We won't force navigation to a specific page since this is an API task,
# but having the browser open is helpful context.
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="