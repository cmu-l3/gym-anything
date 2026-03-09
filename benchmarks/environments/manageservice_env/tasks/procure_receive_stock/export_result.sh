#!/bin/bash
# Export script for "procure_receive_stock"
# Queries SDP database for POs, Line Items, and Assets

echo "=== Exporting Procure & Receive Stock Results ==="
source /workspace/scripts/task_utils.sh

# Output file
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database

# A. Check Vendor
VENDOR_EXISTS=$(sdp_db_exec "SELECT COUNT(*) FROM VendorDefinition WHERE VENDORNAME = 'Dell Inc';")

# B. Check Product
PRODUCT_EXISTS=$(sdp_db_exec "SELECT COUNT(*) FROM ComponentDefinition WHERE COMPONENTNAME = 'Dell Precision 3660';")

# C. Find the Purchase Order
# Look for a PO created after task start, or just the most recent one with this vendor
# We get the ID, Status, and Total
PO_DATA=$(sdp_db_exec "
SELECT 
    po.PURCHASEORDERID, 
    sdef.STATUSNAME, 
    vd.VENDORNAME,
    po.TOTAL_CHARGES
FROM PurchaseOrder po
JOIN VendorDefinition vd ON po.VENDORID = vd.VENDORID
LEFT JOIN StatusDefinition sdef ON po.STATUSID = sdef.STATUSID
WHERE vd.VENDORNAME = 'Dell Inc' 
  AND po.CREATEDTIME >= ${TASK_START}000 
ORDER BY po.CREATEDTIME DESC LIMIT 1;
")

# If SQL returns empty, fill defaults
if [ -z "$PO_DATA" ]; then
    PO_ID="null"
    PO_STATUS="null"
    PO_VENDOR="null"
    PO_TOTAL="0"
else
    # Parse pipe-separated values (default psql output in task_utils might vary, 
    # but sdp_db_exec uses -t -A which is usually pipe or aligned. 
    # Adjusting sdp_db_exec in task_utils usually implies raw output. 
    # Let's assume standard formatting or just grab the fields.)
    PO_ID=$(echo "$PO_DATA" | awk -F'|' '{print $1}')
    PO_STATUS=$(echo "$PO_DATA" | awk -F'|' '{print $2}')
    PO_VENDOR=$(echo "$PO_DATA" | awk -F'|' '{print $3}')
    PO_TOTAL=$(echo "$PO_DATA" | awk -F'|' '{print $4}')
fi

# D. Check Assets
# We look for the 3 specific serial numbers
ASSET_1=$(sdp_db_exec "SELECT RESOURCENAME FROM Resources WHERE SERIALNO = 'DELL-CAD-001';")
ASSET_2=$(sdp_db_exec "SELECT RESOURCENAME FROM Resources WHERE SERIALNO = 'DELL-CAD-002';")
ASSET_3=$(sdp_db_exec "SELECT RESOURCENAME FROM Resources WHERE SERIALNO = 'DELL-CAD-003';")

ASSET_1_TAG=$(sdp_db_exec "SELECT ASSETTAG FROM Resources WHERE SERIALNO = 'DELL-CAD-001';")
ASSET_2_TAG=$(sdp_db_exec "SELECT ASSETTAG FROM Resources WHERE SERIALNO = 'DELL-CAD-002';")
ASSET_3_TAG=$(sdp_db_exec "SELECT ASSETTAG FROM Resources WHERE SERIALNO = 'DELL-CAD-003';")

# E. Check Asset Count increase
INITIAL_ASSET_COUNT=$(cat /tmp/initial_asset_count.txt 2>/dev/null || echo "0")
CURRENT_ASSET_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM Resources WHERE SERIALNO IN ('DELL-CAD-001', 'DELL-CAD-002', 'DELL-CAD-003');")

# 3. Construct JSON
# Note: Python is safer for JSON construction to handle escaping
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'vendor_exists': True if '$VENDOR_EXISTS'.strip() == '1' else False,
    'product_exists': True if '$PRODUCT_EXISTS'.strip() == '1' else False,
    'po': {
        'id': '$PO_ID',
        'status': '$PO_STATUS',
        'vendor': '$PO_VENDOR',
        'total': '$PO_TOTAL'
    },
    'assets': {
        'count_initial': int('$INITIAL_ASSET_COUNT') if '$INITIAL_ASSET_COUNT'.isdigit() else 0,
        'count_current': int('$CURRENT_ASSET_COUNT') if '$CURRENT_ASSET_COUNT'.isdigit() else 0,
        'item1': {'found': bool('$ASSET_1'.strip()), 'tag': '$ASSET_1_TAG'.strip()},
        'item2': {'found': bool('$ASSET_2'.strip()), 'tag': '$ASSET_2_TAG'.strip()},
        'item3': {'found': bool('$ASSET_3'.strip()), 'tag': '$ASSET_3_TAG'.strip()}
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(data, f, indent=2)
"

# Handle permissions
chmod 666 "$RESULT_JSON"

echo "Results exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="