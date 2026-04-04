#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Validate Data Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_validation"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the data processing script with a subtle bug
cat > "$WORKSPACE_DIR/process_orders.py" << 'EOF'
import csv
import json
from datetime import datetime

def parse_price(price_str):
    """Parse price string like '$49.99' to float"""
    return float(price_str.replace('$', '').replace(',', ''))

def transform_order(row):
    """Transform CSV row to JSON order object"""
    order = {
        'order_id': row['OrderID'],
        'customer': row['CustomerName'],
        'date': row['OrderDate'],
        'items': [],
        'total': 0.0
    }
    
    # Parse items (format: "Item1:$10.00,Item2:$20.00")
    items_str = row['Items']
    for item_pair in items_str.split(','):
        if ':' in item_pair:
            name, price = item_pair.split(':')
            item_price = parse_price(price)
            order['items'].append({
                'name': name.strip(),
                'price': item_price
            })
            order['total'] += item_price
    
    # BUG: Total is calculated but doesn't match 'TotalAmount' field
    # Should validate against row['TotalAmount'] or use it instead
    
    return order

def process_orders(input_csv, output_json):
    """Process orders from CSV to JSON"""
    orders = []
    
    with open(input_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            order = transform_order(row)
            orders.append(order)
    
    report = {
        'processed_date': datetime.now().isoformat(),
        'total_orders': len(orders),
        'orders': orders
    }
    
    with open(output_json, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"Processed {len(orders)} orders")
    return report

if __name__ == '__main__':
    process_orders('orders.csv', 'report.json')
EOF

# Create a README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Order Processing Validation

## Task
The `process_orders.py` script transforms order data from CSV to JSON. You need to validate it works correctly.

## Files
- `process_orders.py` - The transformation script
- `orders.csv` - Input data (you need to create this)
- `report.json` - Output data (will be generated)

## Expected CSV Format