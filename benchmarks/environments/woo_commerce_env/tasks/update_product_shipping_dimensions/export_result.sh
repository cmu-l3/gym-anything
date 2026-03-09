#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Output file
RESULT_FILE="/tmp/task_result.json"

# Helper to get shipping meta for a SKU
get_shipping_data() {
    local sku="$1"
    # Get ID
    local pid=$(get_product_by_sku "$sku" | cut -f1)
    
    if [ -z "$pid" ]; then
        echo "null"
        return
    fi

    # Query meta
    local weight=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$pid AND meta_key='_weight'")
    local length=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$pid AND meta_key='_length'")
    local width=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$pid AND meta_key='_width'")
    local height=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$pid AND meta_key='_height'")
    local modified=$(wc_query "SELECT post_modified FROM wp_posts WHERE ID=$pid")

    # Construct JSON object for this product
    cat <<EOF
{
    "id": "$pid",
    "sku": "$sku",
    "found": true,
    "weight": "$(json_escape "$weight")",
    "length": "$(json_escape "$length")",
    "width": "$(json_escape "$width")",
    "height": "$(json_escape "$height")",
    "modified": "$(json_escape "$modified")"
}
EOF
}

# Collect data for all 3 target products
echo "Collecting product data..."
DATA_TABLE=$(get_shipping_data "FURN-OCT-001")
DATA_VASE=$(get_shipping_data "DECOR-VASE-002")
DATA_CURT=$(get_shipping_data "HOME-CURT-003")

# Check if products were found (handle null return from helper)
[ "$DATA_TABLE" == "null" ] && DATA_TABLE='{"found": false, "sku": "FURN-OCT-001"}'
[ "$DATA_VASE" == "null" ] && DATA_VASE='{"found": false, "sku": "DECOR-VASE-002"}'
[ "$DATA_CURT" == "null" ] && DATA_CURT='{"found": false, "sku": "HOME-CURT-003"}'

# Get task timings
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Create final JSON
cat > "$RESULT_FILE" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "task_start_ts": $START_TIME,
    "task_end_ts": $END_TIME,
    "products": {
        "Oak Coffee Table": $DATA_TABLE,
        "Ceramic Vase": $DATA_VASE,
        "Linen Curtains": $DATA_CURT
    }
}
EOF

# Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE"

echo "Export complete. Result:"
cat "$RESULT_FILE"