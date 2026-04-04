#!/bin/bash
# Export script for Bundle Product task

echo "=== Exporting Bundle Product Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Basic Existence Check
TARGET_SKU="CAMP-BUNDLE-001"
echo "Checking for product SKU '$TARGET_SKU'..."
PRODUCT_DATA=$(magento_query "SELECT entity_id, type_id, sku FROM catalog_product_entity WHERE sku='$TARGET_SKU'" 2>/dev/null | tail -1)

FOUND="false"
ENTITY_ID=""
TYPE_ID=""
NAME=""
STATUS=""
SHIPMENT_TYPE=""
OPTIONS_JSON="[]"

if [ -n "$PRODUCT_DATA" ]; then
    FOUND="true"
    ENTITY_ID=$(echo "$PRODUCT_DATA" | cut -f1)
    TYPE_ID=$(echo "$PRODUCT_DATA" | cut -f2)
    
    # Get Name
    NAME=$(get_product_name "$ENTITY_ID")
    
    # Get Status (Attribute ID for status is typically 97, but safe query used)
    STATUS=$(magento_query "SELECT value FROM catalog_product_entity_int 
        WHERE entity_id=$ENTITY_ID 
        AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='status' AND entity_type_id=4)
        AND store_id=0" 2>/dev/null | tail -1)
        
    # Get Shipment Type (Attribute code: shipment_type)
    # 0 = Together, 1 = Separately
    SHIPMENT_TYPE=$(magento_query "SELECT value FROM catalog_product_entity_int 
        WHERE entity_id=$ENTITY_ID 
        AND attribute_id=(SELECT attribute_id FROM eav_attribute WHERE attribute_code='shipment_type' AND entity_type_id=4)
        AND store_id=0" 2>/dev/null | tail -1)

    # Get Bundle Options
    # We need to construct a JSON structure of options and their selections
    
    # Create a temporary python script to format the complex nested data as JSON
    cat > /tmp/export_bundle_data.py << PYEOF
import pymysql
import json
import sys

try:
    conn = pymysql.connect(host='127.0.0.1', user='magento', password='magentopass', db='magento', port=3306)
    cursor = conn.cursor()
    
    product_id = $ENTITY_ID
    
    # Fetch options
    cursor.execute(f"""
        SELECT o.option_id, o.type, o.required, o.position, v.title 
        FROM catalog_product_bundle_option o
        JOIN catalog_product_bundle_option_value v ON o.option_id = v.option_id
        WHERE o.parent_id = {product_id} AND v.store_id = 0
        ORDER BY o.position ASC
    """)
    options_rows = cursor.fetchall()
    
    options = []
    for row in options_rows:
        opt_id, opt_type, opt_req, opt_pos, opt_title = row
        
        # Fetch selections for this option
        cursor.execute(f"""
            SELECT s.selection_id, s.product_id, s.selection_qty, e.sku 
            FROM catalog_product_bundle_selection s
            JOIN catalog_product_entity e ON s.product_id = e.entity_id
            WHERE s.option_id = {opt_id}
        """)
        sel_rows = cursor.fetchall()
        
        selections = []
        for sel in sel_rows:
            sel_id, prod_id, qty, sku = sel
            selections.append({
                "product_id": prod_id,
                "sku": sku,
                "qty": float(qty)
            })
            
        options.append({
            "option_id": opt_id,
            "title": opt_title,
            "type": opt_type,
            "required": bool(opt_req),
            "selections": selections
        })
        
    print(json.dumps(options))
    conn.close()
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

    # Execute inside the container where python3-pymysql is installed
    # Note: The Docker container `magento-mariadb` is where DB lives, but `install_magento.sh` installed 
    # python3-pymysql on the host/VM. We need to forward the port or query via docker exec if using mysql cli.
    # The setup_magento.sh exposes 3306 to localhost, so python on host can access it.
    
    OPTIONS_JSON=$(python3 /tmp/export_bundle_data.py 2>/dev/null || echo "[]")
fi

# Escape strings for JSON
NAME_ESC=$(echo "$NAME" | sed 's/"/\\"/g')
SKU_ESC=$(echo "$TARGET_SKU" | sed 's/"/\\"/g')

# Create result JSON
cat > /tmp/bundle_result_temp.json << EOF
{
    "found": $FOUND,
    "entity_id": "${ENTITY_ID:-}",
    "type_id": "${TYPE_ID:-}",
    "sku": "$SKU_ESC",
    "name": "$NAME_ESC",
    "status": "${STATUS:-0}",
    "shipment_type": "${SHIPMENT_TYPE:-}",
    "options": $OPTIONS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json /tmp/bundle_result_temp.json /tmp/bundle_result.json
rm -f /tmp/bundle_result_temp.json /tmp/export_bundle_data.py

echo "Result exported to /tmp/bundle_result.json"
cat /tmp/bundle_result.json