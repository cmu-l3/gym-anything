#!/bin/bash
set -e
echo "=== Setting up Material Receipt Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
echo "GardenWorld Client ID: $CLIENT_ID"

# 3. Verify required data exists (Vendor and Products)
echo "--- Verifying prerequisite GardenWorld data ---"

# Check Vendor
VENDOR_CHECK=$(idempiere_query "SELECT name FROM c_bpartner WHERE name ILIKE '%Seed Farm%' AND ad_client_id=$CLIENT_ID AND isvendor='Y' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$VENDOR_CHECK" ]; then
    echo "WARNING: Vendor 'Seed Farm Inc.' not found. Task may be difficult."
    # Fallback: List available vendors
    idempiere_query "SELECT name FROM c_bpartner WHERE ad_client_id=$CLIENT_ID AND isvendor='Y' LIMIT 5"
else
    echo "  Vendor found: $VENDOR_CHECK"
fi

# Check Products
AZALEA_CHECK=$(idempiere_query "SELECT name FROM m_product WHERE name ILIKE '%Azalea%' AND ad_client_id=$CLIENT_ID LIMIT 1" 2>/dev/null || echo "")
ELM_CHECK=$(idempiere_query "SELECT name FROM m_product WHERE name ILIKE '%Elm%' AND ad_client_id=$CLIENT_ID LIMIT 1" 2>/dev/null || echo "")

if [ -z "$AZALEA_CHECK" ] || [ -z "$ELM_CHECK" ]; then
    echo "WARNING: One or more products not found ($AZALEA_CHECK, $ELM_CHECK)."
else
    echo "  Products found: $AZALEA_CHECK, $ELM_CHECK"
fi

# 4. Record initial receipt count (to detect new creations)
# Filter for issotrx='N' (Material Receipt/Purchase side)
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inout WHERE ad_client_id=$CLIENT_ID AND issotrx='N'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_receipt_count.txt
echo "Initial material receipt count: $INITIAL_COUNT"

# 5. Ensure Application is ready
# Check if Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard to ensure clean state
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="