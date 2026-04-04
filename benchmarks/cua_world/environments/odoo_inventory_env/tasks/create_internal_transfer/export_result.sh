#!/bin/bash
# Export script for Create Internal Transfer task
# Exports all verification data to JSON file for verifier to read

echo "=== Exporting Create Internal Transfer Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Expected values
TARGET_REFERENCE="TRANSFER-001"
MIN_QUANTITY=10

# Get baseline data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PICKING_COUNT=$(cat /tmp/initial_picking_count.txt 2>/dev/null || echo "0")
INITIAL_MOVE_COUNT=$(cat /tmp/initial_move_count.txt 2>/dev/null || echo "0")
MAX_PICKING_ID_BEFORE=$(cat /tmp/max_picking_id.txt 2>/dev/null || echo "0")

echo "Baseline data:"
echo "  Task start: $TASK_START"
echo "  Initial picking count: $INITIAL_PICKING_COUNT"
echo "  Initial move count: $INITIAL_MOVE_COUNT"
echo "  Max picking ID before: $MAX_PICKING_ID_BEFORE"

# Get current counts
CURRENT_PICKING_COUNT=$(get_stock_picking_count)
CURRENT_MOVE_COUNT=$(get_stock_move_count)

echo "Current counts:"
echo "  Picking count: $CURRENT_PICKING_COUNT (was $INITIAL_PICKING_COUNT)"
echo "  Move count: $CURRENT_MOVE_COUNT (was $INITIAL_MOVE_COUNT)"

# Search for internal transfers created during task
echo ""
echo "Searching for new internal transfers..."

# Internal transfers have picking_type_code = 'internal'
# Also search by reference containing our target
NEW_TRANSFERS=$(odoo_query_rows "SELECT sp.id, sp.name, sp.origin, sp.state, sp.scheduled_date, spt.code as picking_type_code,
                                        sl_src.complete_name as source_location, sl_dst.complete_name as dest_location
                                 FROM stock_picking sp
                                 JOIN stock_picking_type spt ON sp.picking_type_id = spt.id
                                 JOIN stock_location sl_src ON sp.location_id = sl_src.id
                                 JOIN stock_location sl_dst ON sp.location_dest_id = sl_dst.id
                                 WHERE sp.id > $MAX_PICKING_ID_BEFORE
                                 ORDER BY sp.id DESC LIMIT 10")

echo "New transfers found:"
echo "$NEW_TRANSFERS"

# Search for transfer by reference
echo ""
echo "Searching for transfer with reference '$TARGET_REFERENCE'..."
TRANSFER_BY_REF=$(odoo_query_rows "SELECT sp.id, sp.name, sp.origin, sp.state, spt.code as picking_type_code,
                                          sl_src.complete_name as source_location, sl_dst.complete_name as dest_location
                                   FROM stock_picking sp
                                   JOIN stock_picking_type spt ON sp.picking_type_id = spt.id
                                   JOIN stock_location sl_src ON sp.location_id = sl_src.id
                                   JOIN stock_location sl_dst ON sp.location_dest_id = sl_dst.id
                                   WHERE (TRIM(sp.origin) = '$TARGET_REFERENCE' OR TRIM(sp.name) = '$TARGET_REFERENCE')
                                   ORDER BY sp.id DESC LIMIT 1")

# Search for any new internal transfer (backup)
INTERNAL_TRANSFER=$(odoo_query_rows "SELECT sp.id, sp.name, sp.origin, sp.state, spt.code as picking_type_code,
                                            sl_src.complete_name as source_location, sl_dst.complete_name as dest_location
                                     FROM stock_picking sp
                                     JOIN stock_picking_type spt ON sp.picking_type_id = spt.id
                                     JOIN stock_location sl_src ON sp.location_id = sl_src.id
                                     JOIN stock_location sl_dst ON sp.location_dest_id = sl_dst.id
                                     WHERE sp.id > $MAX_PICKING_ID_BEFORE
                                       AND spt.code = 'internal'
                                     ORDER BY sp.id DESC LIMIT 1")

# Determine which transfer to use
TRANSFER_DATA=""
SEARCH_METHOD=""

if [ -n "$TRANSFER_BY_REF" ]; then
    TRANSFER_DATA="$TRANSFER_BY_REF"
    SEARCH_METHOD="reference"
    echo "Found transfer by reference"
elif [ -n "$INTERNAL_TRANSFER" ]; then
    TRANSFER_DATA="$INTERNAL_TRANSFER"
    SEARCH_METHOD="internal_type"
    echo "Found internal transfer by type"
fi

# Parse transfer data
TRANSFER_FOUND="false"
TRANSFER_ID=""
TRANSFER_NAME=""
TRANSFER_ORIGIN=""
TRANSFER_STATE=""
PICKING_TYPE_CODE=""
SOURCE_LOCATION=""
DEST_LOCATION=""

if [ -n "$TRANSFER_DATA" ]; then
    TRANSFER_FOUND="true"
    TRANSFER_ID=$(echo "$TRANSFER_DATA" | cut -f1)
    TRANSFER_NAME=$(echo "$TRANSFER_DATA" | cut -f2)
    TRANSFER_ORIGIN=$(echo "$TRANSFER_DATA" | cut -f3)
    TRANSFER_STATE=$(echo "$TRANSFER_DATA" | cut -f4)
    PICKING_TYPE_CODE=$(echo "$TRANSFER_DATA" | cut -f5)
    SOURCE_LOCATION=$(echo "$TRANSFER_DATA" | cut -f6)
    DEST_LOCATION=$(echo "$TRANSFER_DATA" | cut -f7)

    echo ""
    echo "Transfer details:"
    echo "  ID: $TRANSFER_ID"
    echo "  Name: $TRANSFER_NAME"
    echo "  Origin/Reference: $TRANSFER_ORIGIN"
    echo "  State: $TRANSFER_STATE"
    echo "  Type: $PICKING_TYPE_CODE"
    echo "  Source: $SOURCE_LOCATION"
    echo "  Destination: $DEST_LOCATION"
fi

# Get move lines for this transfer
MOVE_LINES=""
TOTAL_QUANTITY=0
PRODUCT_NAME=""

if [ -n "$TRANSFER_ID" ]; then
    echo ""
    echo "Getting move lines for transfer $TRANSFER_ID..."

    MOVE_LINES=$(odoo_query_rows "SELECT sm.id, pp.name as product, sm.product_uom_qty, sm.state
                                  FROM stock_move sm
                                  JOIN product_product pp ON sm.product_id = pp.id
                                  WHERE sm.picking_id = $TRANSFER_ID
                                  ORDER BY sm.id")

    echo "Move lines:"
    echo "$MOVE_LINES"

    # Get total quantity
    TOTAL_QUANTITY=$(odoo_query "SELECT COALESCE(SUM(product_uom_qty), 0) FROM stock_move WHERE picking_id = $TRANSFER_ID")
    echo "Total quantity in transfer: $TOTAL_QUANTITY"

    # Get first product name
    PRODUCT_NAME=$(odoo_query "SELECT pt.name FROM stock_move sm
                               JOIN product_product pp ON sm.product_id = pp.id
                               JOIN product_template pt ON pp.product_tmpl_id = pt.id
                               WHERE sm.picking_id = $TRANSFER_ID LIMIT 1")
fi

# Validate transfer is internal
IS_INTERNAL="false"
if [ "$PICKING_TYPE_CODE" = "internal" ]; then
    IS_INTERNAL="true"
    echo "Transfer type validation: PASS (internal)"
else
    echo "Transfer type validation: FAIL ($PICKING_TYPE_CODE is not internal)"
fi

# Validate quantity meets minimum
QUANTITY_VALID="false"
if [ -n "$TOTAL_QUANTITY" ]; then
    # Handle floating point comparison
    QTY_INT=${TOTAL_QUANTITY%.*}
    QTY_INT=${QTY_INT:-0}
    if [ "$QTY_INT" -ge "$MIN_QUANTITY" ]; then
        QUANTITY_VALID="true"
        echo "Quantity validation: PASS ($TOTAL_QUANTITY >= $MIN_QUANTITY)"
    else
        echo "Quantity validation: FAIL ($TOTAL_QUANTITY < $MIN_QUANTITY)"
    fi
fi

# Check if newly created
NEWLY_CREATED="false"
if [ -n "$TRANSFER_ID" ] && [ "$TRANSFER_ID" -gt "$MAX_PICKING_ID_BEFORE" ]; then
    NEWLY_CREATED="true"
    echo "Transfer is newly created"
fi

# Escape special characters for JSON
TRANSFER_NAME_ESCAPED=$(json_escape "$TRANSFER_NAME")
TRANSFER_ORIGIN_ESCAPED=$(json_escape "$TRANSFER_ORIGIN")
SOURCE_LOCATION_ESCAPED=$(json_escape "$SOURCE_LOCATION")
DEST_LOCATION_ESCAPED=$(json_escape "$DEST_LOCATION")
PRODUCT_NAME_ESCAPED=$(json_escape "$PRODUCT_NAME")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/internal_transfer_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $(date +%s),
    "initial_picking_count": ${INITIAL_PICKING_COUNT:-0},
    "current_picking_count": ${CURRENT_PICKING_COUNT:-0},
    "initial_move_count": ${INITIAL_MOVE_COUNT:-0},
    "current_move_count": ${CURRENT_MOVE_COUNT:-0},
    "max_picking_id_before": ${MAX_PICKING_ID_BEFORE:-0},
    "transfer_found": $TRANSFER_FOUND,
    "search_method": "$SEARCH_METHOD",
    "newly_created": $NEWLY_CREATED,
    "transfer": {
        "id": "$TRANSFER_ID",
        "name": "$TRANSFER_NAME_ESCAPED",
        "reference": "$TRANSFER_ORIGIN_ESCAPED",
        "state": "$TRANSFER_STATE",
        "picking_type_code": "$PICKING_TYPE_CODE",
        "source_location": "$SOURCE_LOCATION_ESCAPED",
        "dest_location": "$DEST_LOCATION_ESCAPED",
        "total_quantity": ${TOTAL_QUANTITY:-0},
        "product_name": "$PRODUCT_NAME_ESCAPED"
    },
    "validation": {
        "is_internal": $IS_INTERNAL,
        "quantity_valid": $QUANTITY_VALID
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
