#!/bin/bash
set -e
echo "=== Setting up Cash Journal task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Prepare Database State
# ---------------------------------------------------------------
echo "--- Preparing Database ---"

CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    echo "ERROR: Could not find GardenWorld Client ID"
    exit 1
fi
echo "GardenWorld Client ID: $CLIENT_ID"

# Record initial Cash Journal count
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_cash WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_cash_count.txt
echo "Initial Cash Journal count: $INITIAL_COUNT"

# Ensure "Freight" charge exists
FREIGHT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_charge WHERE UPPER(name) LIKE '%FREIGHT%' AND ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
if [ "$FREIGHT_COUNT" -eq 0 ]; then
    echo "Creating Freight charge..."
    # Copy from tax category 
    idempiere_query "INSERT INTO c_charge (c_charge_id, ad_client_id, ad_org_id, isactive, created, createdby, updated, updatedby, name, description, chargeamt, issameaddress, istaxincluded, c_taxcategory_id) SELECT nextval('c_charge_sq'), $CLIENT_ID, 0, 'Y', now(), 100, now(), 100, 'Freight', 'Freight charges', 0, 'N', 'N', min(c_taxcategory_id) FROM c_taxcategory WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || true
fi

# Ensure "Bank Fee" charge exists
BANKFEE_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_charge WHERE (UPPER(name) LIKE '%BANK FEE%' OR UPPER(name) LIKE '%BANK CHARGE%') AND ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
if [ "$BANKFEE_COUNT" -eq 0 ]; then
    echo "Creating Bank Fee charge..."
    idempiere_query "INSERT INTO c_charge (c_charge_id, ad_client_id, ad_org_id, isactive, created, createdby, updated, updatedby, name, description, chargeamt, issameaddress, istaxincluded, c_taxcategory_id) SELECT nextval('c_charge_sq'), $CLIENT_ID, 0, 'Y', now(), 100, now(), 100, 'Bank Fee', 'Bank Service Fee', 0, 'N', 'N', min(c_taxcategory_id) FROM c_taxcategory WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || true
fi

# Ensure a Cash Book exists
CASHBOOK_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_cashbook WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")
if [ "$CASHBOOK_COUNT" -eq 0 ]; then
    echo "Creating Cash Book..."
    CURRENCY_ID=$(idempiere_query "SELECT c_currency_id FROM c_currency WHERE iso_code='USD' LIMIT 1" 2>/dev/null || echo "100")
    idempiere_query "INSERT INTO c_cashbook (c_cashbook_id, ad_client_id, ad_org_id, isactive, created, createdby, updated, updatedby, name, c_currency_id, isdefault) VALUES (nextval('c_cashbook_sq'), $CLIENT_ID, 0, 'Y', now(), 100, now(), 100, 'Cash', $CURRENCY_ID, 'Y')" 2>/dev/null || true
fi

# ---------------------------------------------------------------
# 2. Setup Application State
# ---------------------------------------------------------------
echo "--- Setting up iDempiere UI ---"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla"; then
            break
        fi
        sleep 1
    done
    sleep 10 # Allow page load
fi

# Maximize and focus
DISPLAY=:1 wmctrl -xa firefox 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Navigate to dashboard (reset state)
navigate_to_dashboard

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="