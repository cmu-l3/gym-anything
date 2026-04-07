#!/bin/bash
set -e
echo "=== Setting up create_rfq task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous runs if any (delete topic if exists to ensure fresh start)
# Note: In a real DB with constraints, deleting might fail if linked records exist. 
# We will try to deactivate them instead to avoid constraint violations during setup.
CLIENT_ID=$(get_gardenworld_client_id)
if [ -n "$CLIENT_ID" ]; then
    echo "Deactivating any existing topics named 'Spring Furniture Restock'..."
    idempiere_query "UPDATE c_rfq_topic SET isactive='N', name=name||'_old_'||to_char(now(), 'YYYYMMDDHH24MISS') WHERE name='Spring Furniture Restock' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true
fi

# 2. Record initial counts to detect new records
INITIAL_RFQ_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_rfq WHERE ad_client_id=${CLIENT_ID:-11}" 2>/dev/null || echo "0")
echo "$INITIAL_RFQ_COUNT" > /tmp/initial_rfq_count.txt

# 3. Ensure Firefox is running and navigate to Dashboard
echo "--- Ensuring iDempiere is ready ---"
navigate_to_dashboard

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="