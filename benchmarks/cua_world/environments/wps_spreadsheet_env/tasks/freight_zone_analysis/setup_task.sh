#!/bin/bash
set -e
echo "=== Setting up Freight Zone Analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Documents

# Python script to generate the dataset and ground truth
python3 << 'PYEOF'
import random
import json
import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

random.seed(42)

# Zone mapping
zone_map = {
    'SP': 'Southeast', 'RJ': 'Southeast', 'MG': 'Southeast', 'ES': 'Southeast',
    'PR': 'South', 'SC': 'South', 'RS': 'South',
    'BA': 'Northeast', 'PE': 'Northeast', 'CE': 'Northeast', 'MA': 'Northeast',
    'PB': 'Northeast', 'RN': 'Northeast', 'PI': 'Northeast', 'AL': 'Northeast', 'SE': 'Northeast',
    'AM': 'North', 'PA': 'North', 'AC': 'North', 'RO': 'North', 'RR': 'North', 'AP': 'North', 'TO': 'North',
    'GO': 'Central-West', 'MT': 'Central-West', 'MS': 'Central-West', 'DF': 'Central-West'
}

states = list(zone_map.keys())
weights = [
    (0.1, 1.0, 0.40),
    (1.1, 5.0, 0.30),
    (5.1, 10.0, 0.15),
    (10.1, 30.0, 0.10),
    (30.1, 50.0, 0.05)
]

data = []
for i in range(1, 501):
    order_id = f"ORD{random.randint(10000, 99999)}"
    product_id = f"PRD{random.randint(100, 999)}"
    seller_state = random.choices(states, weights=[10 if s=='SP' else 1 for s in states])[0]
    customer_state = random.choice(states)
    
    # Select weight bracket
    w_min, w_max, _ = random.choices(weights, weights=[w[2] for w in weights])[0]
    weight_kg = round(random.uniform(w_min, w_max), 2)
    
    # Generate realistic prices and freight
    product_price = round(random.uniform(20.0, 1500.0), 2)
    
    # Base freight by weight and zone
    same_zone = zone_map[seller_state] == zone_map[customer_state]
    base_freight = 15.0 if same_zone else 35.0
    freight_value = round(base_freight + (weight_kg * random.uniform(2.0, 5.0)), 2)
    
    # Random date in 2023
    start_date = datetime.date(2023, 1, 1)
    order_date = start_date + datetime.timedelta(days=random.randint(0, 364))
    
    data.append({
        'order_id': order_id,
        'product_id': product_id,
        'seller_state': seller_state,
        'customer_state': customer_state,
        'product_weight_kg': weight_kg,
        'freight_value': freight_value,
        'product_price': product_price,
        'order_date': order_date.isoformat()
    })

# Write to Excel
wb = Workbook()
ws = wb.active
ws.title = "Shipments"

headers = ['order_id', 'product_id', 'seller_state', 'customer_state', 
           'product_weight_kg', 'freight_value', 'product_price', 'order_date']
ws.append(headers)

header_font = Font(bold=True)
header_fill = PatternFill(start_color='DDDDDD', end_color='DDDDDD', fill_type='solid')
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill

for row in data:
    ws.append([
        row['order_id'], row['product_id'], row['seller_state'], row['customer_state'],
        row['product_weight_kg'], row['freight_value'], row['product_price'], row['order_date']
    ])

# Adjust columns
for col in ['A', 'B', 'H']: ws.column_dimensions[col].width = 15
for col in ['C', 'D']: ws.column_dimensions[col].width = 10
for col in ['E', 'F', 'G']: ws.column_dimensions[col].width = 18

ws2 = wb.create_sheet("ZoneLookup")
ws2.append(['state_code', 'zone_name'])
for cell in ws2[1]:
    cell.font = header_font
    cell.fill = header_fill

for state, zone in sorted(zone_map.items()):
    ws2.append([state, zone])

wb.save('/home/ga/Documents/freight_data.xlsx')

# Compute Ground Truth
def get_bracket(w):
    if w <= 1: return '0-1kg'
    elif w <= 5: return '1-5kg'
    elif w <= 10: return '5-10kg'
    elif w <= 30: return '10-30kg'
    else: return '30+kg'

# Enrich data internally
for row in data:
    row['zone'] = zone_map[row['customer_state']]
    row['bracket'] = get_bracket(row['product_weight_kg'])
    row['cpk'] = row['freight_value'] / row['product_weight_kg']
    row['fpct'] = (row['freight_value'] / row['product_price']) * 100

zones = ['Southeast', 'South', 'Northeast', 'North', 'Central-West']
brackets = ['0-1kg', '1-5kg', '5-10kg', '10-30kg', '30+kg']

gt = {"matrix": {}, "zone_avg": {}, "bracket_avg": {}, "overall_avg": 0, "total_shipments": len(data), "total_freight": sum(r['freight_value'] for r in data), "avg_freight_pct": sum(r['fpct'] for r in data) / len(data)}

for z in zones:
    gt["matrix"][z] = {}
    z_data = [r for r in data if r['zone'] == z]
    for b in brackets:
        bz_data = [r for r in z_data if r['bracket'] == b]
        gt["matrix"][z][b] = sum(r['cpk'] for r in bz_data) / len(bz_data) if bz_data else None
    gt["zone_avg"][z] = sum(r['cpk'] for r in z_data) / len(z_data) if z_data else None

for b in brackets:
    b_data = [r for r in data if r['bracket'] == b]
    gt["bracket_avg"][b] = sum(r['cpk'] for r in b_data) / len(b_data) if b_data else None

gt["overall_avg"] = sum(r['cpk'] for r in data) / len(data)

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(gt, f)
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/freight_data.xlsx
chmod 600 /tmp/ground_truth.json

# Kill any existing WPS instances
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 2

# Launch WPS Spreadsheet with the data file
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et /home/ga/Documents/freight_data.xlsx &"
sleep 8

# Wait for WPS window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "freight_data|WPS Spreadsheets|\.xlsx"; then
        break
    fi
    sleep 1
done

# Dismiss any potential popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take an initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="