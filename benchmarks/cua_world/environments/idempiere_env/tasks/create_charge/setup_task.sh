#!/bin/bash
set -e
echo "=== Setting up create_charge task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Get Client ID (GardenWorld)
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    echo "WARNING: Could not determine GardenWorld Client ID, defaulting to 11"
    CLIENT_ID=11
fi

# Clean up any existing record with this key to ensure fresh start
echo "Cleaning up existing data for WTF-001..."
CHARGE_ID=$(idempiere_query "SELECT c_charge_id FROM c_charge WHERE value='WTF-001' AND ad_client_id=$CLIENT_ID" 2>/dev/null || true)
if [ -n "$CHARGE_ID" ] && [ "$CHARGE_ID" != "0" ]; then
    echo "Found existing charge (ID: $CHARGE_ID), deleting..."
    # Delete dependent records first (accounting, translations)
    idempiere_query "DELETE FROM c_charge_acct WHERE c_charge_id=$CHARGE_ID" 2>/dev/null || true
    idempiere_query "DELETE FROM c_charge_trl WHERE c_charge_id=$CHARGE_ID" 2>/dev/null || true
    idempiere_query "DELETE FROM c_charge WHERE c_charge_id=$CHARGE_ID" 2>/dev/null || true
fi

# Record initial count
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_charge WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_charge_count.txt
echo "Initial charge count: $INITIAL_COUNT"

# Ensure iDempiere is open and ready
echo "Ensuring iDempiere is running..."
ensure_idempiere_open ""

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="