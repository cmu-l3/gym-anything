#!/bin/bash
echo "=== Exporting Restock Pharmacy Inventory Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Define Expected Values
TARGET_LOT="SIM-2025-X84"
DRUG_NAME="Simvastatin 20mg"

# 4. Query for the specific transaction
# We look in drug_inventory (or drug_sales for some versions, but inventory adds are usually drug_inventory or drug_transactions)
# Standard OpenEMR/LibreHealth usually uses `drug_inventory` for batches.
# We look for the Lot Number specifically.

# Get the transaction details
# Schema often: inventory_id, drug_id, lot_number, expiration, quantity, vendor_id, manufacture_date...
QUERY="SELECT quantity, lot_number, expiration, vendor_id, trans_date 
       FROM drug_inventory 
       WHERE lot_number='${TARGET_LOT}' 
       ORDER BY inventory_id DESC LIMIT 1"

# We use a temp file to parse the result safely
RESULT_STR=$(librehealth_query "$QUERY")
# Result format will be tab separated: "500  SIM-2025-X84  2028-12-31  PharmaDistro Inc  2025-..."

# Parse the result
# Note: vendor_id might be an ID or text depending on version. 
# If it's empty, the query failed to find the lot.

FOUND_QTY="0"
FOUND_LOT=""
FOUND_EXP=""
FOUND_VENDOR=""
TRANS_DATE=""

if [ -n "$RESULT_STR" ]; then
    FOUND_QTY=$(echo "$RESULT_STR" | awk '{print $1}')
    FOUND_LOT=$(echo "$RESULT_STR" | awk '{print $2}')
    FOUND_EXP=$(echo "$RESULT_STR" | awk '{print $3}')
    # Vendor might contain spaces, so we take the rest of the line, carefully handling columns
    # Actually, let's query columns individually to be safe against spaces
    
    FOUND_QTY=$(librehealth_query "SELECT quantity FROM drug_inventory WHERE lot_number='${TARGET_LOT}' LIMIT 1")
    FOUND_LOT=$(librehealth_query "SELECT lot_number FROM drug_inventory WHERE lot_number='${TARGET_LOT}' LIMIT 1")
    FOUND_EXP=$(librehealth_query "SELECT expiration FROM drug_inventory WHERE lot_number='${TARGET_LOT}' LIMIT 1")
    # Vendor usually stored as text in newer versions or ID. We'll check what we get.
    # Note: LibreHealth sometimes calls the table `drug_inventory`
    FOUND_VENDOR=$(librehealth_query "SELECT vendor_id FROM drug_inventory WHERE lot_number='${TARGET_LOT}' LIMIT 1")
fi

# 5. Check Stock Level Change
# Get Drug ID first
DRUG_ID=$(librehealth_query "SELECT drug_id FROM drugs WHERE name='${DRUG_NAME}' LIMIT 1")
CURRENT_STOCK=$(librehealth_query "SELECT stock_level FROM drugs WHERE drug_id='${DRUG_ID}'")
if [ -z "$CURRENT_STOCK" ]; then CURRENT_STOCK=0; fi

INITIAL_STOCK=$(cat /tmp/initial_stock_level.txt 2>/dev/null || echo "0")
STOCK_DIFF=$((CURRENT_STOCK - INITIAL_STOCK))

# 6. Verify Transaction Timestamp (Anti-gaming)
# We check if the record was created recently.
# Since we don't have a reliable `created_at` in all versions, we rely on the fact that the Lot Number is unique to this task.
# The Setup script didn't create this lot, so if it exists, the agent created it.

# 7. Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "transaction_found": $(if [ -n "$FOUND_LOT" ]; then echo "true"; else echo "false"; fi),
    "found_lot": "$FOUND_LOT",
    "found_qty": "$FOUND_QTY",
    "found_exp": "$FOUND_EXP",
    "found_vendor": "$FOUND_VENDOR",
    "initial_stock": $INITIAL_STOCK,
    "current_stock": $CURRENT_STOCK,
    "stock_diff": $STOCK_DIFF,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="