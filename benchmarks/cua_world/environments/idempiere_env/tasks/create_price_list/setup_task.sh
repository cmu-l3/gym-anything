#!/bin/bash
set -e
echo "=== Setting up create_price_list task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Get GardenWorld client ID (usually 11)
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    echo "ERROR: Could not determine GardenWorld Client ID"
    exit 1
fi
echo "GardenWorld client ID: $CLIENT_ID"

# 1. Clean up if the price list already exists (Idempotency)
echo "--- Checking for existing data ---"
EXISTING_ID=$(idempiere_query "SELECT m_pricelist_id FROM m_pricelist WHERE name='2025 Spring Retail' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")

if [ -n "$EXISTING_ID" ]; then
    echo "WARNING: Price list '2025 Spring Retail' already exists (ID: $EXISTING_ID). Cleaning up..."
    
    # Delete product prices associated with versions of this price list
    idempiere_query "DELETE FROM m_productprice WHERE m_pricelist_version_id IN (SELECT m_pricelist_version_id FROM m_pricelist_version WHERE m_pricelist_id=$EXISTING_ID)" 2>/dev/null || true
    
    # Delete versions
    idempiere_query "DELETE FROM m_pricelist_version WHERE m_pricelist_id=$EXISTING_ID" 2>/dev/null || true
    
    # Delete the price list
    idempiere_query "DELETE FROM m_pricelist WHERE m_pricelist_id=$EXISTING_ID" 2>/dev/null || true
    
    echo "Cleanup complete."
fi

# 2. Record initial price list count
INITIAL_PL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_pricelist WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
echo "$INITIAL_PL_COUNT" > /tmp/initial_pricelist_count.txt
echo "Initial price list count: $INITIAL_PL_COUNT"

# 3. Ensure Firefox is open and on iDempiere dashboard
echo "--- Ensuring iDempiere is ready ---"
ensure_idempiere_open ""

# Maximize Firefox
DISPLAY=:1 wmctrl -xa firefox 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="