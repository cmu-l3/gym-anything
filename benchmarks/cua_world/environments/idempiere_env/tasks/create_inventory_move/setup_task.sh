#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_inventory_move task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Get Client and Warehouse IDs
CLIENT_ID=$(get_gardenworld_client_id)
HQ_WAREHOUSE_ID=$(idempiere_query "SELECT m_warehouse_id FROM m_warehouse WHERE ad_client_id=$CLIENT_ID AND isactive='Y' ORDER BY m_warehouse_id LIMIT 1" 2>/dev/null || echo "")

# 3. Record initial M_Movement count
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_movement WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_movement_count.txt
echo "Initial M_Movement count: $INITIAL_COUNT"

# 4. Ensure Product 'Azalea Bush' exists
PRODUCT_ID=$(idempiere_query "SELECT m_product_id FROM m_product WHERE ad_client_id=$CLIENT_ID AND isactive='Y' AND LOWER(name) LIKE '%azalea%bush%' LIMIT 1" 2>/dev/null || echo "")

if [ -z "$PRODUCT_ID" ]; then
    echo "WARNING: Azalea Bush not found. This might be a data issue."
else
    echo "Azalea Bush product ID: $PRODUCT_ID"
fi

# 5. Ensure multiple Locators exist in HQ Warehouse
LOCATOR_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_locator WHERE m_warehouse_id=$HQ_WAREHOUSE_ID AND isactive='Y'" 2>/dev/null || echo "0")
echo "Locator count in HQ Warehouse: $LOCATOR_COUNT"

if [ "$LOCATOR_COUNT" -lt 2 ]; then
    echo "Creating additional locator in HQ Warehouse..."
    ORG_ID=$(idempiere_query "SELECT ad_org_id FROM m_warehouse WHERE m_warehouse_id=$HQ_WAREHOUSE_ID LIMIT 1")
    # Determine new ID
    NEXT_LOC_ID=$(idempiere_query "SELECT COALESCE(MAX(m_locator_id),999999)+1 FROM m_locator")
    
    # Insert new locator
    idempiere_query "INSERT INTO m_locator (m_locator_id, ad_client_id, ad_org_id, m_warehouse_id, value, x, y, z, isactive, created, createdby, updated, updatedby, isdefault, m_locator_uu)
        VALUES ($NEXT_LOC_ID, $CLIENT_ID, $ORG_ID, $HQ_WAREHOUSE_ID, 'Transfer-Loc-B', 'Row2', 'Aisle1', 'Bin1', 'Y', NOW(), 100, NOW(), 100, 'N', uuid_generate_v4())" 2>/dev/null || true
    echo "Created locator Transfer-Loc-B"
fi

# 6. Ensure sufficient stock exists for the product
# Get primary locator
FIRST_LOCATOR_ID=$(idempiere_query "SELECT m_locator_id FROM m_locator WHERE m_warehouse_id=$HQ_WAREHOUSE_ID AND isactive='Y' ORDER BY isdefault DESC, m_locator_id LIMIT 1")

if [ -n "$PRODUCT_ID" ] && [ -n "$FIRST_LOCATOR_ID" ]; then
    TOTAL_ONHAND=$(idempiere_query "SELECT COALESCE(SUM(qtyonhand),0) FROM m_storageonhand WHERE m_product_id=$PRODUCT_ID" 2>/dev/null || echo "0")
    echo "Total on-hand qty for Azalea Bush: $TOTAL_ONHAND"

    # Seed stock if low (< 5)
    IS_LOW=$(echo "$TOTAL_ONHAND < 5" | bc -l 2>/dev/null || echo "1")
    if [ "$IS_LOW" = "1" ]; then
        echo "Insufficient stock. Seeding 20 units of Azalea Bush..."
        ASI_ID=0
        ORG_ID=$(idempiere_query "SELECT ad_org_id FROM m_warehouse WHERE m_warehouse_id=$HQ_WAREHOUSE_ID LIMIT 1")
        
        # Check if record exists for update, else insert
        EXISTING=$(idempiere_query "SELECT COUNT(*) FROM m_storageonhand WHERE m_product_id=$PRODUCT_ID AND m_locator_id=$FIRST_LOCATOR_ID AND m_attributesetinstance_id=$ASI_ID" 2>/dev/null || echo "0")
        
        if [ "$EXISTING" -gt 0 ]; then
            idempiere_query "UPDATE m_storageonhand SET qtyonhand = qtyonhand + 20, updated=NOW() WHERE m_product_id=$PRODUCT_ID AND m_locator_id=$FIRST_LOCATOR_ID AND m_attributesetinstance_id=$ASI_ID" 2>/dev/null || true
        else
            idempiere_query "INSERT INTO m_storageonhand (m_product_id, m_locator_id, m_attributesetinstance_id, ad_client_id, ad_org_id, qtyonhand, datematerialpolicy, isactive, created, createdby, updated, updatedby, m_storageonhand_uu)
                VALUES ($PRODUCT_ID, $FIRST_LOCATOR_ID, $ASI_ID, $CLIENT_ID, $ORG_ID, 20, NOW(), 'Y', NOW(), 100, NOW(), 100, uuid_generate_v4())" 2>/dev/null || true
        fi
        echo "Stock seeded."
    fi
fi

# 7. Ensure Firefox is open and on Dashboard
echo "--- Ensuring Firefox is on iDempiere dashboard ---"
ensure_idempiere_open ""

# Focus and maximize Firefox
DISPLAY=:1 wmctrl -xa firefox 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="