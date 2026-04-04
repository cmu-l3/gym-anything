#!/bin/bash
echo "=== Exporting standardize_product_attribute result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Target Product ID
PRODUCT_ID=$(cat /tmp/target_product_id.txt 2>/dev/null)

if [ -z "$PRODUCT_ID" ]; then
    # Fallback: look it up by name
    PRODUCT_ID=$(wc_query "SELECT ID FROM wp_posts WHERE post_title='Eco-Friendly Sneaker' AND post_type='product' LIMIT 1")
fi

echo "Target Product ID: $PRODUCT_ID"

# Use Python to extract and inspect the complex serialized data
# We output a JSON that the host verifier can parse easily
python3 -c "
import pymysql
import json
import sys

result = {
    'product_found': False,
    'attributes_raw': '',
    'has_global_color': False,
    'has_custom_color': False,
    'has_custom_material': False,
    'term_linked': False,
    'term_name': '',
    'error': ''
}

try:
    product_id = '$PRODUCT_ID'
    if not product_id:
        raise Exception('Product ID not found')

    conn = pymysql.connect(host='127.0.0.1', user='wordpress', password='wordpresspass', database='wordpress')
    cursor = conn.cursor()

    # 1. Get raw serialized attributes
    cursor.execute(\"SELECT meta_value FROM wp_postmeta WHERE post_id=%s AND meta_key='_product_attributes'\", (product_id,))
    row = cursor.fetchone()
    
    if row:
        result['product_found'] = True
        raw_attrs = row[0] # This is a string (serialized PHP)
        result['attributes_raw'] = raw_attrs

        # We perform basic string analysis here in the container as a first pass
        # Real verification happens on host, but this helps debug
        
        # Check for Global Color (pa_color)
        # In serialized array, global attributes usually use their slug as key: s:8:\"pa_color\"
        if 's:8:\"pa_color\"' in raw_attrs:
            result['has_global_color'] = True
            
        # Check for Custom Color removal
        # Custom usually keyed by name if entered manually, or sanitized name
        # If the old custom 'Color' exists, we might see s:5:\"Color\" ... s:11:\"is_taxonomy\";i:0
        # If global 'Color' exists, we might see s:5:\"Color\" ... s:11:\"is_taxonomy\";i:1 (if label is Color)
        # But global usually keyed as pa_color.
        
        # We'll export the raw string and let the robust verifier handle parsing.
    
    # 2. Check Term Relationship (Is it linked to 'green' in 'pa_color'?)
    cursor.execute(\"\"\"
        SELECT t.name 
        FROM wp_term_relationships tr
        JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
        JOIN wp_terms t ON tt.term_id = t.term_id
        WHERE tr.object_id = %s AND tt.taxonomy = 'pa_color'
    \"\"\", (product_id,))
    
    terms = cursor.fetchall()
    term_names = [t[0].lower() for t in terms]
    
    if 'green' in term_names:
        result['term_linked'] = True
        result['term_name'] = 'green'

except Exception as e:
    result['error'] = str(e)
    
print(json.dumps(result))
" > /tmp/raw_result.json

# Combine into final task result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "product_id": "$PRODUCT_ID",
    "db_check": $(cat /tmp/raw_result.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json