#!/bin/bash
# Export script for Export Filtered Products CSV task

echo "=== Exporting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/clothing_prices.csv"

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check Output File Status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy the CSV to temp for verifier to read
    cp "$OUTPUT_PATH" /tmp/exported_products.csv
    chmod 666 /tmp/exported_products.csv
fi

# 3. Generate Ground Truth Data (Snapshot of DB)
# We execute python inside the container to query the DB and produce a clean JSON
# of what SHOULD be in the CSV. This makes verification robust against DB changes.
cat > /tmp/generate_ground_truth.py << 'PYEOF'
import json
import pymysql
import os

# Connect to DB (using settings from setup_woocommerce.sh)
conn = pymysql.connect(
    host='127.0.0.1',
    user='wordpress',
    password='wordpresspass',
    db='wordpress',
    charset='utf8mb4',
    cursorclass=pymysql.cursors.DictCursor
)

try:
    with conn.cursor() as cursor:
        # Get all products in 'Clothing' category
        # Select standard columns usually exported by WooCommerce
        sql = """
        SELECT 
            p.ID,
            p.post_title as 'Name',
            pm_sku.meta_value as 'SKU',
            pm_price.meta_value as 'Regular price'
        FROM wp_posts p
        JOIN wp_term_relationships tr ON p.ID = tr.object_id
        JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id
        JOIN wp_terms t ON tt.term_id = t.term_id
        LEFT JOIN wp_postmeta pm_sku ON p.ID = pm_sku.post_id AND pm_sku.meta_key = '_sku'
        LEFT JOIN wp_postmeta pm_price ON p.ID = pm_price.post_id AND pm_price.meta_key = '_regular_price'
        WHERE p.post_type = 'product' 
        AND p.post_status = 'publish'
        AND t.name = 'Clothing'
        AND tt.taxonomy = 'product_cat'
        """
        cursor.execute(sql)
        products = cursor.fetchall()
        
        # Clean up data (handle None)
        for p in products:
            if p['SKU'] is None: p['SKU'] = ""
            if p['Regular price'] is None: p['Regular price'] = ""
            
        with open('/tmp/ground_truth.json', 'w') as f:
            json.dump(products, f)
            
finally:
    conn.close()
PYEOF

# Run the ground truth generator
python3 /tmp/generate_ground_truth.py 2>/dev/null || echo "[]" > /tmp/ground_truth.json
chmod 666 /tmp/ground_truth.json

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "csv_path": "/tmp/exported_products.csv",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="