#!/bin/bash
# Export script for execute_woocommerce_bulk_price_update
# Gathers all product prices and compares them against the initial baseline.

echo "=== Exporting bulk price update results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract Data using Python
cat << 'EOF' > /tmp/export_data.py
import subprocess
import json
import os

if not os.path.exists('/tmp/baseline_products.json'):
    print("Error: Baseline products file not found.")
    exit(1)

with open('/tmp/baseline_products.json', 'r') as f:
    baseline = json.load(f)

results = {
    "products": [],
    "task_start_time": 0
}

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

for pid, data in baseline.items():
    # Get post status
    res = subprocess.run(f"wp post get {pid} --field=post_status --path=/var/www/html/wordpress --allow-root", shell=True, capture_output=True, text=True)
    status = res.stdout.strip()
    
    # Get current regular price
    res_price = subprocess.run(f"wp post meta get {pid} _regular_price --path=/var/www/html/wordpress --allow-root", shell=True, capture_output=True, text=True)
    current_price_str = res_price.stdout.strip()
    
    try:
        current_price = float(current_price_str)
    except ValueError:
        current_price = -1.0 # Indicator for missing/invalid price
        
    results["products"].append({
        "id": pid,
        "name": data["name"],
        "category": data["cat"],
        "initial_price": data["initial_price"],
        "actual_price": current_price,
        "status": status
    })

with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)
EOF

echo "Extracting post metadata..."
python3 /tmp/export_data.py

# Move to safe location with correct permissions
rm -f /tmp/bulk_update_result.json 2>/dev/null || sudo rm -f /tmp/bulk_update_result.json 2>/dev/null || true
cp /tmp/task_result.json /tmp/bulk_update_result.json 2>/dev/null || sudo cp /tmp/task_result.json /tmp/bulk_update_result.json
chmod 666 /tmp/bulk_update_result.json 2>/dev/null || sudo chmod 666 /tmp/bulk_update_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/bulk_update_result.json"
cat /tmp/bulk_update_result.json
echo ""
echo "=== Export complete ==="