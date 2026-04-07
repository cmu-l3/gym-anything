#!/bin/bash
echo "=== Exporting restructure_product_catalog_hierarchy results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Extract Product Categories
echo "Extracting Product Categories..."
suitecrm_db_query "SELECT id, name, IFNULL(parent_category_id, '') FROM aos_product_categories WHERE deleted=0;" > /tmp/categories.tsv

# Extract Target Products
echo "Extracting Target Products..."
suitecrm_db_query "SELECT id, name, IFNULL(aos_product_category_id, '') FROM aos_products WHERE id IN ('prod-wifi-cam-0000-000000000001', 'prod-motion-sen-0000-000000000001', 'prod-smart-hub-0000-000000000001') AND deleted=0;" > /tmp/products.tsv

# Build JSON using Python to avoid bash escaping issues
python3 << 'EOF' > /tmp/export_payload.json
import json, csv, os

result = {
    "task_start": int(os.environ.get('TASK_START', 0)),
    "task_end": int(os.environ.get('TASK_END', 0)),
    "categories": [],
    "products": []
}

if os.path.exists('/tmp/categories.tsv'):
    with open('/tmp/categories.tsv', 'r') as f:
        reader = csv.reader(f, delimiter='\t')
        for row in reader:
            if len(row) >= 3:
                result["categories"].append({
                    "id": row[0].strip(),
                    "name": row[1].strip(),
                    "parent_id": row[2].strip()
                })

if os.path.exists('/tmp/products.tsv'):
    with open('/tmp/products.tsv', 'r') as f:
        reader = csv.reader(f, delimiter='\t')
        for row in reader:
            if len(row) >= 3:
                result["products"].append({
                    "id": row[0].strip(),
                    "name": row[1].strip(),
                    "category_id": row[2].strip()
                })

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Ensure safe permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="