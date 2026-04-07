#!/bin/bash
set -e
echo "=== Setting up provision_mfa_rd_lab task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

wait_for_ac_demo

# Ensure authentication for cleanup
ac_login > /dev/null 2>&1 || true

# Helper function to delete pre-existing items to guarantee a clean starting state
delete_by_name() {
    local endpoint="$1"
    local name="$2"
    local items=$(ac_api GET "$endpoint" 2>/dev/null || echo "[]")
    
    # Extract IDs safely ignoring jq parse errors if HTML is returned
    local ids=$(echo "$items" | jq -r ".[] | select(.name==\"$name\") | .id" 2>/dev/null || true)
    
    for id in $ids; do
        if [ -n "$id" ] && [ "$id" != "null" ]; then
            ac_api DELETE "$endpoint/$id" > /dev/null 2>&1
            echo "Cleaned up existing '$name' from $endpoint (id: $id)"
        fi
    done
}

# Clean up any potential artifacts from previous runs
delete_by_name "/zones" "R&D Lab"
delete_by_name "/accessRules" "Lab Access"
delete_by_name "/access-rules" "Lab Access"

# Launch browser directly to the Zones page
launch_firefox_to "${AC_URL}/#/zones" 8

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="