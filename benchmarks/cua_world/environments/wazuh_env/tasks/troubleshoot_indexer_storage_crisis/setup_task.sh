#!/bin/bash
set -e
echo "=== Setting up Indexer Storage Crisis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Indexer is running
echo "Waiting for Indexer to be ready..."
wait_for_service "Wazuh Indexer" "check_indexer_health" 180

# 1. Create dummy legacy indices to simulate old data
echo "Creating legacy indices..."
for i in {01..05}; do
    INDEX_NAME="wazuh-alerts-2023.01.$i"
    wazuh_indexer_query "/$INDEX_NAME" '{"settings": {"number_of_shards": 1, "number_of_replicas": 0}}' > /dev/null
done

# 2. Ensure a current index exists
CURRENT_DATE=$(date +%Y.%m.%d)
CURRENT_INDEX="wazuh-alerts-4.x-$CURRENT_DATE"
wazuh_indexer_query "/$CURRENT_INDEX" '{"settings": {"number_of_shards": 1, "number_of_replicas": 0}}' > /dev/null

# 3. Simulate "Disk Flood Stage" by forcing read-only block
# We apply this to ALL wazuh-alerts-* indices
echo "Applying read_only_allow_delete block to indices..."
wazuh_indexer_query "/wazuh-alerts-*/_settings" \
    '{"index": {"blocks": {"read_only_allow_delete": true}}}'

# 4. Flush indices to ensure settings persist
wazuh_indexer_query "/_flush"

# Verify the block is active
echo "Verifying block status..."
SETTINGS=$(wazuh_indexer_query "/$CURRENT_INDEX/_settings")
if echo "$SETTINGS" | grep -q "read_only_allow_delete.*true"; then
    echo "CRISIS SIMULATED: Indices are now read-only."
else
    echo "WARNING: Failed to apply read-only block."
fi

# Open terminal for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="