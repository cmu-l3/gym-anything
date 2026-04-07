#!/bin/bash
echo "=== Setting up receive_purchase_order task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup existing specific records if any (to ensure clean state)
echo "Cleaning up any existing target records..."
vtiger_db_query "DELETE e FROM vtiger_crmentity e JOIN vtiger_purchaseorder p ON e.crmid = p.purchaseorderid WHERE p.subject = 'Restock Milwaukee Tools Q1'"
vtiger_db_query "DELETE FROM vtiger_purchaseorder WHERE subject = 'Restock Milwaukee Tools Q1'"
vtiger_db_query "DELETE e FROM vtiger_crmentity e JOIN vtiger_products p ON e.crmid = p.productid WHERE p.productname = 'Milwaukee M18 Impact Driver'"
vtiger_db_query "DELETE FROM vtiger_products WHERE productname = 'Milwaukee M18 Impact Driver'"
vtiger_db_query "DELETE e FROM vtiger_crmentity e JOIN vtiger_vendor v ON e.crmid = v.vendorid WHERE v.vendorname = 'Midwest Tool Supply'"
vtiger_db_query "DELETE FROM vtiger_vendor WHERE vendorname = 'Midwest Tool Supply'"

# 3. Seed the prerequisite data directly using sequence generation
echo "Seeding prerequisite Vendor, Product, and Purchase Order..."
NEXT_ID=$(vtiger_db_query "SELECT id FROM vtiger_crmentity_seq LIMIT 1" | tr -d '[:space:]')
if [ -z "$NEXT_ID" ]; then
    NEXT_ID=50000
    vtiger_db_query "INSERT INTO vtiger_crmentity_seq (id) VALUES ($NEXT_ID)"
fi

VENDOR_ID=$NEXT_ID
PRODUCT_ID=$((NEXT_ID + 1))
PO_ID=$((NEXT_ID + 2))
NEW_SEQ=$((NEXT_ID + 3))

# Update sequence
vtiger_db_query "UPDATE vtiger_crmentity_seq SET id = $NEW_SEQ"

# Insert Vendor: Midwest Tool Supply
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($VENDOR_ID, 1, 1, 'Vendors', NOW(), NOW(), 1, 0, 'Midwest Tool Supply')"
vtiger_db_query "INSERT INTO vtiger_vendor (vendorid, vendorname) VALUES ($VENDOR_ID, 'Midwest Tool Supply')"
vtiger_db_query "INSERT INTO vtiger_vendorcf (vendorid) VALUES ($VENDOR_ID)"

# Insert Product: Milwaukee M18 Impact Driver (initial stock: 150)
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($PRODUCT_ID, 1, 1, 'Products', NOW(), NOW(), 1, 0, 'Milwaukee M18 Impact Driver')"
vtiger_db_query "INSERT INTO vtiger_products (productid, productname, product_no, qtyinstock, unit_price) VALUES ($PRODUCT_ID, 'Milwaukee M18 Impact Driver', 'PRO-MW18', 150, 99.00)"
vtiger_db_query "INSERT INTO vtiger_productcf (productid) VALUES ($PRODUCT_ID)"

# Insert Purchase Order: Restock Milwaukee Tools Q1
vtiger_db_query "INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($PO_ID, 1, 1, 'PurchaseOrder', NOW(), NOW(), 1, 0, 'Restock Milwaukee Tools Q1')"
vtiger_db_query "INSERT INTO vtiger_purchaseorder (purchaseorderid, subject, vendorid, postatus, tracking_no, carrier, currency_id, conversion_rate) VALUES ($PO_ID, 'Restock Milwaukee Tools Q1', $VENDOR_ID, 'Approved', '', '', 1, 1)"
vtiger_db_query "INSERT INTO vtiger_purchaseordercf (purchaseorderid) VALUES ($PO_ID)"

# Link Product to Purchase Order (Line Item, Quantity: 40)
vtiger_db_query "INSERT INTO vtiger_inventoryproductrel (id, productid, sequence_no, quantity, listprice) VALUES ($PO_ID, $PRODUCT_ID, 1, 40, 99.00)"

echo "Prerequisite records created successfully."

# 4. Record initial stock for verification
INITIAL_STOCK=$(vtiger_db_query "SELECT qtyinstock FROM vtiger_products WHERE productid=$PRODUCT_ID" | tr -d '[:space:]')
echo "Initial product stock: $INITIAL_STOCK"
echo "$INITIAL_STOCK" > /tmp/initial_product_stock.txt

# 5. Ensure logged in and navigate to Purchase Orders list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=PurchaseOrder&view=List"
sleep 4

# 6. Take initial screenshot
take_screenshot /tmp/receive_po_initial.png

echo "=== receive_purchase_order task setup complete ==="