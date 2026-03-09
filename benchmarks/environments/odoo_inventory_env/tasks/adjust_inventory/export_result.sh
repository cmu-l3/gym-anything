#!/bin/bash
# Export script for Adjust Inventory task
# Exports verification data to check if inventory was adjusted to 50 units

echo "=== Exporting Adjust Inventory Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Expected values
TARGET_QUANTITY=50

# Get baseline data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_QUANT_COUNT=$(cat /tmp/initial_quant_count.txt 2>/dev/null || echo "0")
MAX_QUANT_ID_BEFORE=$(cat /tmp/max_quant_id.txt 2>/dev/null || echo "0")
STOCK_LOCATION=$(cat /tmp/stock_location_id.txt 2>/dev/null || echo "0")
TARGET_PRODUCT_ID=$(cat /tmp/target_product_id.txt 2>/dev/null || echo "")
TARGET_PRODUCT_NAME=$(cat /tmp/target_product_name.txt 2>/dev/null || echo "")
INITIAL_QUANTITY=$(cat /tmp/initial_quantity.txt 2>/dev/null || echo "0")

echo "Baseline data:"
echo "  Task start: $TASK_START"
echo "  Stock location: $STOCK_LOCATION"
echo "  Target product ID: $TARGET_PRODUCT_ID"
echo "  Target product name: $TARGET_PRODUCT_NAME"
echo "  Initial quantity: $INITIAL_QUANTITY"

# Get current quant count
CURRENT_QUANT_COUNT=$(get_stock_quant_count)
echo "Current quant count: $CURRENT_QUANT_COUNT (was $INITIAL_QUANT_COUNT)"

# Search for products with quantity = 50 in stock location
echo ""
echo "Searching for products with quantity = 50..."

PRODUCTS_AT_50=$(odoo_query_rows "SELECT sq.product_id, pt.name, sq.quantity, sq.id as quant_id
                                  FROM stock_quant sq
                                  JOIN product_product pp ON sq.product_id = pp.id
                                  JOIN product_template pt ON pp.product_tmpl_id = pt.id
                                  WHERE sq.location_id = $STOCK_LOCATION
                                    AND sq.quantity = 50
                                  ORDER BY sq.write_date DESC")

echo "Products at 50 units:"
echo "$PRODUCTS_AT_50"

# Check if target product now has 50 units
ADJUSTMENT_FOUND="false"
ADJUSTED_PRODUCT_ID=""
ADJUSTED_PRODUCT_NAME=""
CURRENT_QUANTITY=0

if [ -n "$TARGET_PRODUCT_ID" ]; then
    echo ""
    echo "Checking target product ($TARGET_PRODUCT_NAME)..."

    CURRENT_QUANTITY=$(odoo_query "SELECT COALESCE(quantity, 0) FROM stock_quant
                                   WHERE product_id = $TARGET_PRODUCT_ID AND location_id = $STOCK_LOCATION")

    echo "Target product current quantity: $CURRENT_QUANTITY"

    if [ "${CURRENT_QUANTITY%.*}" = "50" ] || [ "$CURRENT_QUANTITY" = "50.0" ] || [ "$CURRENT_QUANTITY" = "50.00" ]; then
        ADJUSTMENT_FOUND="true"
        ADJUSTED_PRODUCT_ID="$TARGET_PRODUCT_ID"
        ADJUSTED_PRODUCT_NAME="$TARGET_PRODUCT_NAME"
        echo "Target product adjusted to 50!"
    fi
fi

# If target wasn't adjusted to 50, check if any product was set to 50
if [ "$ADJUSTMENT_FOUND" = "false" ] && [ -n "$PRODUCTS_AT_50" ]; then
    echo ""
    echo "Checking if any product was adjusted to 50..."

    # Check each product at 50 to see if it changed
    while IFS=$'\t' read -r prod_id prod_name prod_qty quant_id; do
        if [ -n "$prod_id" ]; then
            # Check if this quantity changed (quant was updated or created)
            if [ "$quant_id" -gt "$MAX_QUANT_ID_BEFORE" ]; then
                ADJUSTMENT_FOUND="true"
                ADJUSTED_PRODUCT_ID="$prod_id"
                ADJUSTED_PRODUCT_NAME="$prod_name"
                CURRENT_QUANTITY="$prod_qty"
                echo "Found new quant at 50: $prod_name (quant_id=$quant_id > $MAX_QUANT_ID_BEFORE)"
                break
            fi
        fi
    done <<< "$PRODUCTS_AT_50"
fi

# Check stock move history for inventory adjustments
echo ""
echo "Checking for inventory adjustment moves..."

ADJUSTMENT_MOVES=$(odoo_query_rows "SELECT sm.id, sm.product_id, pt.name->>'en_US', sm.product_uom_qty, sm.reference, sm.state
                                     FROM stock_move sm
                                     JOIN product_product pp ON sm.product_id = pp.id
                                     JOIN product_template pt ON pp.product_tmpl_id = pt.id
                                     WHERE sm.create_date > NOW() - INTERVAL '1 hour'
                                       AND (sm.reference LIKE '%Inventory%' OR sm.reference LIKE '%Adjustment%' OR sm.reference LIKE '%Count%')
                                     ORDER BY sm.id DESC LIMIT 5")

echo "Recent adjustment moves:"
echo "$ADJUSTMENT_MOVES"

# Extract the reason/reference from stock quant changes (Odoo 17+)
# In Odoo 17, inventory adjustments create stock_quant_adjustment records or use stock.move.line with reference
echo ""
echo "Checking for adjustment reason/reference..."
ADJUSTMENT_REASON=""

# Try stock.quant history
QUANT_HISTORY=$(odoo_query "SELECT reference FROM stock_move_line
                             WHERE product_id = $TARGET_PRODUCT_ID
                               AND create_date > NOW() - INTERVAL '1 hour'
                             ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

if [ -n "$QUANT_HISTORY" ]; then
    ADJUSTMENT_REASON="$QUANT_HISTORY"
    echo "Found reason from stock_move_line: $ADJUSTMENT_REASON"
fi

# Also check stock.picking name/origin
if [ -z "$ADJUSTMENT_REASON" ]; then
    PICKING_REASON=$(odoo_query "SELECT sp.origin FROM stock_picking sp
                                  JOIN stock_move sm ON sm.picking_id = sp.id
                                  WHERE sm.product_id = $TARGET_PRODUCT_ID
                                    AND sp.create_date > NOW() - INTERVAL '1 hour'
                                  ORDER BY sp.id DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$PICKING_REASON" ]; then
        ADJUSTMENT_REASON="$PICKING_REASON"
        echo "Found reason from stock_picking origin: $ADJUSTMENT_REASON"
    fi
fi

# Check for 'Annual Stock Count' - ALL keywords must be present (not just one)
REASON_VALID="false"
if [ -n "$ADJUSTMENT_REASON" ]; then
    REASON_LOWER=$(echo "$ADJUSTMENT_REASON" | tr '[:upper:]' '[:lower:]')
    # Check if ALL required keywords are present (annual AND stock AND count)
    HAS_ANNUAL=$(echo "$REASON_LOWER" | grep -qi "annual" && echo "1" || echo "0")
    HAS_STOCK=$(echo "$REASON_LOWER" | grep -qi "stock" && echo "1" || echo "0")
    HAS_COUNT=$(echo "$REASON_LOWER" | grep -qi "count" && echo "1" || echo "0")

    if [ "$HAS_ANNUAL" = "1" ] && [ "$HAS_STOCK" = "1" ] && [ "$HAS_COUNT" = "1" ]; then
        REASON_VALID="true"
        echo "Reason contains ALL expected keywords (annual, stock, count): $ADJUSTMENT_REASON"
    else
        echo "Reason DOES NOT contain all required keywords: $ADJUSTMENT_REASON"
        echo "  Has 'annual': $HAS_ANNUAL, Has 'stock': $HAS_STOCK, Has 'count': $HAS_COUNT"
    fi
fi

# Also check stock.inventory if it exists (depends on Odoo version)
INVENTORY_ADJUSTMENTS=$(odoo_query_rows "SELECT id, name, state, date
                                          FROM stock_inventory
                                          WHERE create_date > NOW() - INTERVAL '1 hour'
                                          ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "")

if [ -n "$INVENTORY_ADJUSTMENTS" ]; then
    echo ""
    echo "Recent inventory objects:"
    echo "$INVENTORY_ADJUSTMENTS"
fi

# Quantity change validation
QUANTITY_CHANGED="false"
if [ -n "$INITIAL_QUANTITY" ] && [ -n "$CURRENT_QUANTITY" ]; then
    if [ "$INITIAL_QUANTITY" != "$CURRENT_QUANTITY" ]; then
        QUANTITY_CHANGED="true"
        echo "Quantity changed from $INITIAL_QUANTITY to $CURRENT_QUANTITY"
    fi
fi

# Escape special characters for JSON
ADJUSTED_PRODUCT_NAME_ESCAPED=$(json_escape "$ADJUSTED_PRODUCT_NAME")
TARGET_PRODUCT_NAME_ESCAPED=$(json_escape "$TARGET_PRODUCT_NAME")
ADJUSTMENT_REASON_ESCAPED=$(json_escape "$ADJUSTMENT_REASON")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/adjust_inventory_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $(date +%s),
    "target_quantity": $TARGET_QUANTITY,
    "stock_location_id": ${STOCK_LOCATION:-0},
    "initial_quant_count": ${INITIAL_QUANT_COUNT:-0},
    "current_quant_count": ${CURRENT_QUANT_COUNT:-0},
    "adjustment_found": $ADJUSTMENT_FOUND,
    "quantity_changed": $QUANTITY_CHANGED,
    "adjustment_reason": "$ADJUSTMENT_REASON_ESCAPED",
    "reason_valid": $REASON_VALID,
    "target_product": {
        "id": "$TARGET_PRODUCT_ID",
        "name": "$TARGET_PRODUCT_NAME_ESCAPED",
        "initial_quantity": ${INITIAL_QUANTITY:-0},
        "current_quantity": ${CURRENT_QUANTITY:-0}
    },
    "adjusted_product": {
        "id": "$ADJUSTED_PRODUCT_ID",
        "name": "$ADJUSTED_PRODUCT_NAME_ESCAPED",
        "quantity": ${CURRENT_QUANTITY:-0}
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
