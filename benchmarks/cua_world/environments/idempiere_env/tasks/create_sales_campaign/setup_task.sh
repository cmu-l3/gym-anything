#!/bin/bash
set -e
echo "=== Setting up create_sales_campaign task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Get Client ID (GardenWorld)
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    echo "ERROR: Could not determine GardenWorld Client ID"
    exit 1
fi

# Clean up any previous existence of this specific campaign (Idempotency)
echo "--- Checking for existing campaign ---"
EXISTING_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_campaign WHERE value='SPRING-GARDEN-2025' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
if [ "$EXISTING_COUNT" -gt 0 ]; then
    echo "Cleaning up existing campaign record..."
    # Deactivate and rename to avoid conflicts if delete fails due to constraints
    idempiere_query "UPDATE c_campaign SET value=value||'_OLD_'||to_char(now(),'HH24MISS'), isactive='N' WHERE value='SPRING-GARDEN-2025' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
fi

# Record initial overall campaign count for anti-gaming
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_campaign WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_campaign_count.txt
echo "Initial campaign count: $INITIAL_COUNT"

# Ensure Firefox is open and at iDempiere dashboard
echo "--- Ensuring iDempiere is ready ---"
ensure_idempiere_open ""

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="