#!/bin/bash
echo "=== Setting up broadcast_maintenance_message task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Artifactory is ready
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# 2. Reset System Message to known clean state (Disabled, Empty)
# We use a small python script to construct the XML payload because 
# Artifactory config API expects the FULL config or a specific patch.
# However, modifying system config via REST API in OSS can be tricky if not sending full XML.
# But for setup, we want to ensure the message isn't already there.
# We will use the REST API to disable it if possible, or just accept current state 
# and rely on the agent to change it.
# To be safe against "do nothing" gaming, we verify the specific message text isn't already set.

CURRENT_CONFIG=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

# Check if our target message already exists (unlikely, but good to check)
TARGET_MSG="Scheduled Maintenance: Saturday, Oct 24th at 02:00 UTC. System will be read-only."
if echo "$CURRENT_CONFIG" | grep -Fq "$TARGET_MSG"; then
    echo "WARNING: Target message already exists. Attempting to clear..."
    # We won't attempt complex XML manipulation in bash to clear it, 
    # but we will note this in a timestamp file to potentially fail or warn.
    # ideally we would post a clean config, but extracting and reposting full config is fragile.
fi

# 3. Record start time
date +%s > /tmp/task_start_time.txt

# 4. Prepare Firefox
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/artifactory/general_settings/system_message"
sleep 5

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="