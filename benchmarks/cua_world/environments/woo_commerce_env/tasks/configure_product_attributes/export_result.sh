#!/bin/bash
# Export script for Configure Product Attributes task

echo "=== Exporting Configure Product Attributes Result ==="

source /workspace/scripts/task_utils.sh

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# DATA COLLECTION
# ==============================================================================

# 1. Get Global Attributes
# Returns JSON array of attributes
ATTRIBUTES_JSON=$(wc_query_headers "SELECT attribute_id, attribute_name, attribute_label, attribute_type 
    FROM wp_woocommerce_attribute_taxonomies" | python3 -c '
import sys, csv, json
reader = csv.DictReader(sys.stdin, delimiter="\t")
print(json.dumps(list(reader)))
')

# 2. Get Terms for Color and Material
# We look for terms in taxonomies "pa_color" and "pa_material"
TERMS_JSON=$(wc_query_headers "SELECT t.name, t.slug, tt.taxonomy
    FROM wp_terms t
    JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
    WHERE tt.taxonomy IN ('pa_color', 'pa_material')" | python3 -c '
import sys, csv, json
reader = csv.DictReader(sys.stdin, delimiter="\t")
print(json.dumps(list(reader)))
')

# 3. Get Product Assignments & Visibility
# We need to fetch the products and check their relationships and meta data
# Target SKUs: OCT-BLK-M (T-Shirt), SFDJ-BLU-32 (Jeans), MWS-GRY-L (Sweater)

get_product_data() {
    local sku="$1"
    
    # Get ID
    local id_res=$(get_product_by_sku "$sku")
    local id=$(echo "$id_res" | cut -f1)
    
    if [ -z "$id" ]; then
        echo "{}"
        return
    fi

    # Get Assigned Terms (via relationships)
    # Returns comma separated list of term names
    local terms=$(wc_query "SELECT GROUP_CONCAT(t.name)
        FROM wp_terms t
        JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id
        WHERE tr.object_id = $id AND tt.taxonomy IN ('pa_color', 'pa_material')")
    
    # Get Raw Meta for Visibility Check
    # serialized PHP array stored in _product_attributes
    local meta=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$id AND meta_key='_product_attributes'")
    
    # JSON Escape
    local meta_esc=$(json_escape "$meta")
    local terms_esc=$(json_escape "$terms")
    
    echo "{\"sku\": \"$sku\", \"id\": \"$id\", \"assigned_terms\": \"$terms_esc\", \"attribute_meta\": \"$meta_esc\"}"
}

P1_JSON=$(get_product_data "OCT-BLK-M")
P2_JSON=$(get_product_data "SFDJ-BLU-32")
P3_JSON=$(get_product_data "MWS-GRY-L")

# Create Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "attributes": $ATTRIBUTES_JSON,
    "terms": $TERMS_JSON,
    "products": {
        "tshirt": $P1_JSON,
        "jeans": $P2_JSON,
        "sweater": $P3_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json
cat /tmp/task_result.json
echo "=== Export Complete ==="