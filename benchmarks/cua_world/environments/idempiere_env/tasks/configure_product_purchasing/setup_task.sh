#!/bin/bash
set -e
echo "=== Setting up configure_product_purchasing task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------------
# 1. Database Setup: Ensure Product and Vendor exist, and clean up old POs
# -----------------------------------------------------------------------------
echo "--- Preparing Database State ---"

# Get Client ID for GardenWorld (usually 11)
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11
    echo "Warning: Could not determine GardenWorld Client ID, defaulting to 11"
fi

# A. Ensure Product 'Heavy Duty Tarp' exists
# We check if it exists; if not, we insert a basic record.
# M_Product_Category_ID=12 (Supplies), C_UOM_ID=100 (Each), C_TaxCategory_ID=10 (Standard) are standard GardenWorld IDs.
PRODUCT_CHECK=$(idempiere_query "SELECT m_product_id FROM m_product WHERE name='Heavy Duty Tarp' AND ad_client_id=$CLIENT_ID")

if [ -z "$PRODUCT_CHECK" ]; then
    echo "Creating product 'Heavy Duty Tarp'..."
    idempiere_query "INSERT INTO m_product (
        m_product_id, ad_client_id, ad_org_id, isactive, created, createdby, updated, updatedby,
        value, name, m_product_category_id, c_uom_id, isstocked, ispurchased, issold, c_taxcategory_id
    ) VALUES (
        nextval('m_product_seq'), $CLIENT_ID, 0, 'Y', now(), 100, now(), 100,
        'TARP-HD-001', 'Heavy Duty Tarp', 12, 100, 'Y', 'Y', 'Y', 10
    )"
else
    echo "Product 'Heavy Duty Tarp' already exists."
fi

# B. Ensure Vendor 'Industrial Supply Co' exists
# C_BP_Group_ID=103 (Vendors US)
VENDOR_CHECK=$(idempiere_query "SELECT c_bpartner_id FROM c_bpartner WHERE name='Industrial Supply Co' AND ad_client_id=$CLIENT_ID")

if [ -z "$VENDOR_CHECK" ]; then
    echo "Creating vendor 'Industrial Supply Co'..."
    idempiere_query "INSERT INTO c_bpartner (
        c_bpartner_id, ad_client_id, ad_org_id, isactive, created, createdby, updated, updatedby,
        value, name, isvendor, iscustomer, c_bp_group_id
    ) VALUES (
        nextval('c_bpartner_seq'), $CLIENT_ID, 0, 'Y', now(), 100, now(), 100,
        'INDSUPPLY001', 'Industrial Supply Co', 'Y', 'N', 103
    )"
else
    echo "Vendor 'Industrial Supply Co' already exists."
fi

# C. Clean up any existing Purchasing Record (M_Product_PO) for this combo
# This ensures the agent must actually create it.
echo "Cleaning up existing purchasing records..."
idempiere_query "DELETE FROM m_product_po 
WHERE m_product_id IN (SELECT m_product_id FROM m_product WHERE name='Heavy Duty Tarp' AND ad_client_id=$CLIENT_ID)
AND c_bpartner_id IN (SELECT c_bpartner_id FROM c_bpartner WHERE name='Industrial Supply Co' AND ad_client_id=$CLIENT_ID)"

# -----------------------------------------------------------------------------
# 2. Application Setup
# -----------------------------------------------------------------------------
echo "--- Navigating to iDempiere ---"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to reset state
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="