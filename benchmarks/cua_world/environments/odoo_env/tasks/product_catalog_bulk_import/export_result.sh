#!/bin/bash
echo "=== Exporting Product Import Results ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python/XML-RPC to verify the database state
# We query by the known SKUs from the CSV file
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

# Odoo Connection Details
url = "http://localhost:8069"
db = "odoo_demo"
username = "admin@example.com"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))
except Exception as e:
    print(f"Connection error: {e}")
    # Write minimal error result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e), "found_count": 0}, f)
    sys.exit(0)

# The SKUs we expect to find
expected_skus = [
    'PEN-GEL-BLK', 'PEN-GEL-BLU', 'PEN-GEL-RED', 'PCL-MECH-05', 'REF-LEAD-HB',
    'PAP-A4-500', 'PAP-A3-100', 'NOT-STK-YEL', 'NB-SPI-RUL', 'DSK-TAPE-DISP',
    'DSK-STAP-STD', 'REF-STAP-266', 'DSK-ORG-MESH', 'MRK-WHT-SET', 'COR-TAPE-5MM'
]

print(f"Querying Odoo for {len(expected_skus)} SKUs...")

# Search for products
domain = [['default_code', 'in', expected_skus]]
fields = ['name', 'default_code', 'list_price', 'standard_price', 'categ_id', 'weight', 'create_date']
products = models.execute_kw(db, uid, password, 'product.product', 'search_read', [domain], {'fields': fields})

found_skus = []
product_details = {}

for p in products:
    sku = p.get('default_code')
    found_skus.append(sku)
    
    # Store details for verification
    # categ_id returns [id, name] e.g. [5, "Office Paper"]
    cat_name = p.get('categ_id', [0, ""])[1] if p.get('categ_id') else ""
    
    product_details[sku] = {
        "name": p.get('name'),
        "list_price": p.get('list_price'),
        "standard_price": p.get('standard_price'),
        "category": cat_name,
        "weight": p.get('weight'),
        "id": p.get('id')
    }

print(f"Found {len(products)} matching products.")

# Compile result
result = {
    "found_count": len(products),
    "found_skus": found_skus,
    "product_data": product_details,
    "timestamp": datetime.datetime.now().isoformat(),
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="