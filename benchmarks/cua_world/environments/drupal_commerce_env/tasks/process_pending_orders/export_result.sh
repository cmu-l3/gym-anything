#!/bin/bash
echo "=== Exporting Process Pending Orders Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if we have the order IDs from setup
if [ ! -f /tmp/task_order_ids.json ]; then
    echo "ERROR: Task order IDs file missing. Setup may have failed."
    echo '{"error": "setup_failed"}' > /tmp/task_result.json
    exit 0
fi

# Read the IDs from the JSON file
# We use a python script to query the database for these specific IDs and construct the result
cat > /tmp/check_orders.py << 'PYEOF'
import json
import subprocess
import sys

def run_query(query):
    cmd = ["docker", "exec", "drupal-mariadb", "mysql", "-u", "drupal", "-pdrupalpass", "drupal", "-N", "-e", query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8').strip()
        return result
    except subprocess.CalledProcessError:
        return ""

try:
    with open('/tmp/task_order_ids.json', 'r') as f:
        orders = json.load(f)
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)

results = []

for order_info in orders:
    oid = order_info['id']
    if not oid:
        continue
        
    # Get current state from DB
    state = run_query(f"SELECT state FROM commerce_order WHERE order_id = {oid}")
    
    results.append({
        "id": oid,
        "sku": order_info['sku'],
        "customer": order_info['customer'],
        "final_state": state
    })

output = {
    "orders": results,
    "timestamp": run_query("SELECT NOW()")
}

print(json.dumps(output))
PYEOF

# Run the python script and save output
python3 /tmp/check_orders.py > /tmp/task_result.json 2>/dev/null

# Clean up permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="