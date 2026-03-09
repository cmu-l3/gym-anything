#!/bin/bash
# Export script for Create Product task
# Exports all verification data to JSON file for verifier to read

echo "=== Exporting Create Product Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target product details
TARGET_NAME="Industrial Safety Helmet"
TARGET_REF="HELM-IND-001"
TARGET_BARCODE="5901234123457"

# Get baseline data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PRODUCT_COUNT=$(cat /tmp/initial_product_count.txt 2>/dev/null || echo "0")
MAX_PRODUCT_ID_BEFORE=$(cat /tmp/max_product_id.txt 2>/dev/null || echo "0")

echo "Baseline data:"
echo "  Task start: $TASK_START"
echo "  Initial product count: $INITIAL_PRODUCT_COUNT"
echo "  Max product ID before: $MAX_PRODUCT_ID_BEFORE"

# Get current product count
CURRENT_PRODUCT_COUNT=$(get_product_count)
echo "Current product count: $CURRENT_PRODUCT_COUNT (was $INITIAL_PRODUCT_COUNT)"

# Search for the product by EXACT name (case-insensitive)
# Odoo 17 stores name as JSONB: {"en_US": "Product Name"}
# Barcode is in product_product table, not product_template
# Cost (standard_price) in Odoo 17 is stored in ir.property
echo ""
echo "Searching for product by EXACT name: '$TARGET_NAME'..."
# EXACT match only - no LIKE/wildcards to prevent gaming
PRODUCT_BY_NAME=$(odoo_query_rows "SELECT pt.id, pt.name->>'en_US' as name, pt.default_code, pp.barcode, pt.list_price, pt.detailed_type FROM product_template pt LEFT JOIN product_product pp ON pp.product_tmpl_id = pt.id WHERE LOWER(TRIM(pt.name->>'en_US')) = LOWER('$TARGET_NAME') ORDER BY pt.id DESC LIMIT 1")

# Search by internal reference
echo "Searching for product by reference: '$TARGET_REF'..."
PRODUCT_BY_REF=$(odoo_query_rows "SELECT pt.id, pt.name->>'en_US' as name, pt.default_code, pp.barcode, pt.list_price, pt.detailed_type FROM product_template pt LEFT JOIN product_product pp ON pp.product_tmpl_id = pt.id WHERE pt.default_code = '$TARGET_REF' ORDER BY pt.id DESC LIMIT 1")

# Search by barcode (in product_product table)
echo "Searching for product by barcode: '$TARGET_BARCODE'..."
PRODUCT_BY_BARCODE=$(odoo_query_rows "SELECT pt.id, pt.name->>'en_US' as name, pt.default_code, pp.barcode, pt.list_price, pt.detailed_type FROM product_template pt JOIN product_product pp ON pp.product_tmpl_id = pt.id WHERE pp.barcode = '$TARGET_BARCODE' ORDER BY pt.id DESC LIMIT 1")

# Debug: Show all recent products
echo ""
echo "=== DEBUG: Recent products (id > $MAX_PRODUCT_ID_BEFORE) ==="
odoo_query "SELECT pt.id, pt.name->>'en_US' as name, pt.default_code, pp.barcode, pt.detailed_type FROM product_template pt LEFT JOIN product_product pp ON pp.product_tmpl_id = pt.id WHERE pt.id > $MAX_PRODUCT_ID_BEFORE ORDER BY pt.id DESC LIMIT 10"
echo "=== END DEBUG ==="

# Determine which product to use (prefer by name, then ref, then barcode)
PRODUCT_DATA=""
SEARCH_METHOD=""

if [ -n "$PRODUCT_BY_NAME" ]; then
    PRODUCT_DATA="$PRODUCT_BY_NAME"
    SEARCH_METHOD="name"
    echo "Found product by name"
elif [ -n "$PRODUCT_BY_REF" ]; then
    PRODUCT_DATA="$PRODUCT_BY_REF"
    SEARCH_METHOD="reference"
    echo "Found product by internal reference"
elif [ -n "$PRODUCT_BY_BARCODE" ]; then
    PRODUCT_DATA="$PRODUCT_BY_BARCODE"
    SEARCH_METHOD="barcode"
    echo "Found product by barcode"
fi

# Parse product data (6 fields: id, name, default_code, barcode, list_price, detailed_type)
PRODUCT_FOUND="false"
PRODUCT_ID=""
PRODUCT_NAME=""
PRODUCT_REF=""
PRODUCT_BARCODE=""
PRODUCT_SALES_PRICE=""
PRODUCT_COST="0"
PRODUCT_TYPE=""

if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1 | tr -d '[:space:]')
    PRODUCT_NAME=$(echo "$PRODUCT_DATA" | cut -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    PRODUCT_REF=$(echo "$PRODUCT_DATA" | cut -f3 | tr -d '[:space:]')
    PRODUCT_BARCODE=$(echo "$PRODUCT_DATA" | cut -f4 | tr -d '[:space:]')
    PRODUCT_SALES_PRICE=$(echo "$PRODUCT_DATA" | cut -f5 | tr -d '[:space:]')
    PRODUCT_TYPE=$(echo "$PRODUCT_DATA" | cut -f6 | tr -d '[:space:]')

    # Get cost (standard_price) from ir.property table in Odoo 17
    # In Odoo 17, standard_price is stored in ir_property with res_id = 'product.product,<id>'
    if [ -n "$PRODUCT_ID" ]; then
        # First get the product.product id from product.template id
        PP_ID=$(odoo_query "SELECT id FROM product_product WHERE product_tmpl_id = $PRODUCT_ID LIMIT 1")
        if [ -n "$PP_ID" ]; then
            # Query ir_property for standard_price
            PRODUCT_COST=$(odoo_query "SELECT COALESCE(value_float, 0) FROM ir_property WHERE name='standard_price' AND res_id='product.product,$PP_ID' LIMIT 1")
            # If not in ir_property, try the direct column (some Odoo versions)
            if [ -z "$PRODUCT_COST" ] || [ "$PRODUCT_COST" = "" ]; then
                PRODUCT_COST=$(odoo_query "SELECT COALESCE(standard_price, 0) FROM product_product WHERE id = $PP_ID")
            fi
        fi
        # Default to 0 if still not found
        [ -z "$PRODUCT_COST" ] && PRODUCT_COST="0"
    fi

    echo ""
    echo "Product details found:"
    echo "  ID: $PRODUCT_ID"
    echo "  Name: $PRODUCT_NAME"
    echo "  Internal Ref: $PRODUCT_REF"
    echo "  Barcode: $PRODUCT_BARCODE"
    echo "  Sales Price: $PRODUCT_SALES_PRICE"
    echo "  Type: $PRODUCT_TYPE"
fi

# Check if product is newly created (ID > max_before)
NEWLY_CREATED="false"
if [ -n "$PRODUCT_ID" ]; then
    if [ "$PRODUCT_ID" -gt "$MAX_PRODUCT_ID_BEFORE" ]; then
        NEWLY_CREATED="true"
        echo "Product is newly created (id $PRODUCT_ID > $MAX_PRODUCT_ID_BEFORE)"
    else
        echo "WARNING: Product exists but may have been pre-existing (id $PRODUCT_ID <= $MAX_PRODUCT_ID_BEFORE)"
    fi
fi

# Validate product type (should be 'product' for storable)
TYPE_VALID="false"
if [ "$PRODUCT_TYPE" = "product" ]; then
    TYPE_VALID="true"
    echo "Product type is correct: storable (product)"
elif [ -n "$PRODUCT_TYPE" ]; then
    echo "Product type is: $PRODUCT_TYPE (expected: product)"
fi

# Escape special characters for JSON
PRODUCT_NAME_ESCAPED=$(json_escape "$PRODUCT_NAME")
PRODUCT_REF_ESCAPED=$(json_escape "$PRODUCT_REF")
PRODUCT_BARCODE_ESCAPED=$(json_escape "$PRODUCT_BARCODE")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_product_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $(date +%s),
    "initial_product_count": ${INITIAL_PRODUCT_COUNT:-0},
    "current_product_count": ${CURRENT_PRODUCT_COUNT:-0},
    "max_product_id_before": ${MAX_PRODUCT_ID_BEFORE:-0},
    "product_found": $PRODUCT_FOUND,
    "search_method": "$SEARCH_METHOD",
    "newly_created": $NEWLY_CREATED,
    "product": {
        "id": "$PRODUCT_ID",
        "name": "$PRODUCT_NAME_ESCAPED",
        "internal_reference": "$PRODUCT_REF_ESCAPED",
        "barcode": "$PRODUCT_BARCODE_ESCAPED",
        "sales_price": "${PRODUCT_SALES_PRICE:-0}",
        "cost": "${PRODUCT_COST:-0}",
        "type": "$PRODUCT_TYPE"
    },
    "validation": {
        "type_valid": $TYPE_VALID
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
