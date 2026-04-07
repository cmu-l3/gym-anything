#!/bin/bash
set -euo pipefail

echo "=== Setting up build_supplier_scorecard task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

DATA_DIR="/home/ga/Documents"
TRUTH_DIR="/var/lib/task_ground_truth"
mkdir -p "$DATA_DIR"
sudo mkdir -p "$TRUTH_DIR"
sudo chown -R ga:ga "$TRUTH_DIR"

# Generate the data preparation script
cat > /tmp/prepare_data.py << 'PYEOF'
import csv
import json
import urllib.request
import datetime
from collections import defaultdict
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment

# URL for USAID Supply Chain Dataset (filtered sample for reliability or load full)
URL = "https://data.usaid.gov/api/views/a3rc-nmf6/rows.csv?accessType=DOWNLOAD"

print("Downloading dataset...")
try:
    req = urllib.request.Request(URL, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=30) as response:
        lines = [line.decode('utf-8') for line in response.readlines()]
    reader = csv.DictReader(lines)
    raw_data = list(reader)
except Exception as e:
    print(f"Download failed: {e}. Using bundled/synthetic real-pattern data fallback.")
    # Fallback to ensure task always runs even if external API is down
    raw_data = []
    vendors = ["Aurobindo Pharma Limited", "Cipla", "Hetero Unit III Hyderabad IN", "Mylan (formerly Matrix)", "Novartis Pharma AG", "Strides Arcolab Limited", "Abbott GmbH & Co. KG", "Bristol-Myers Squibb", "GlaxoSmithKline", "Janssen-Cilag", "Merck Sharp & Dohme", "Pfizer", "Roche", "Sanofi-Aventis", "Teva Pharmaceutical"]
    for i in range(300):
        v = vendors[i % 15]
        raw_data.append({
            'Vendor': v,
            'Country': 'Zambia',
            'Shipment Mode': 'Air',
            'Scheduled Delivery Date': '01-Jan-20',
            'Delivered to Client Date': '05-Jan-20' if i % 4 != 0 else '15-Jan-20',
            'Product Group': 'ARV',
            'Line Item Quantity': str((i * 17 % 100) + 10),
            'Unit Price': str((i * 3.14 % 50) + 1.5),
            'Line Item Value': str(((i * 17 % 100) + 10) * ((i * 3.14 % 50) + 1.5)),
            'Freight Cost (USD)': '150.00'
        })

# Process and filter data
vendors_count = defaultdict(int)
valid_rows = []

for row in raw_data:
    try:
        vendor = row.get('Vendor')
        if not vendor or vendor == 'N/A' or vendor == 'SCMS from RDC':
            continue
            
        qty = int(float(row.get('Line Item Quantity', 0)))
        price = float(row.get('Unit Price', 0))
        value = float(row.get('Line Item Value', 0))
        
        if qty <= 0 or price <= 0:
            continue
            
        # Parse dates to calculate on-time
        sched_str = row.get('Scheduled Delivery Date', '')
        actual_str = row.get('Delivered to Client Date', '')
        
        # Simple date parsing logic (handles common formats in this dataset)
        try:
            if '-' in sched_str:
                sched_date = datetime.datetime.strptime(sched_str, '%d-%b-%y')
                actual_date = datetime.datetime.strptime(actual_str, '%d-%b-%y')
            else:
                sched_date = datetime.datetime.strptime(sched_str, '%Y-%m-%d')
                actual_date = datetime.datetime.strptime(actual_str, '%Y-%m-%d')
                
            days_diff = (actual_date - sched_date).days
            on_time = 1 if days_diff <= 7 else 0
        except:
            on_time = 1 if (qty % 3 != 0) else 0  # fallback logic if date parsing fails
            
        valid_rows.append({
            'Vendor': vendor,
            'Country': row.get('Country', 'Unknown'),
            'Shipment_Mode': row.get('Shipment Mode', 'Unknown'),
            'Scheduled_Delivery': sched_str,
            'Actual_Delivery': actual_str,
            'Product_Group': row.get('Product Group', 'Unknown'),
            'Quantity': qty,
            'Unit_Price': price,
            'Line_Item_Value': value,
            'Freight_Cost': float(row.get('Freight Cost (USD)', 0) or 0),
            'On_Time': on_time
        })
        vendors_count[vendor] += 1
    except Exception as e:
        continue

# Select top 15 vendors
top_vendors = [v for v, c in sorted(vendors_count.items(), key=lambda x: x[1], reverse=True)[:15]]

# Filter rows to only these vendors, sample ~200 rows total to keep it manageable
final_rows = []
vendor_tracker = defaultdict(int)

for row in valid_rows:
    v = row['Vendor']
    if v in top_vendors and vendor_tracker[v] < 20: # Cap at 20 per vendor
        final_rows.append(row)
        vendor_tracker[v] += 1
        if len(final_rows) >= 200 and all(c >= 5 for c in vendor_tracker.values()):
            break

# Ensure we have exactly 15 vendors
unique_vendors = sorted(list(set(r['Vendor'] for r in final_rows)))

# Generate Truth JSON
truth = {
    "vendors": unique_vendors,
    "metrics": {}
}

for v in unique_vendors:
    v_rows = [r for r in final_rows if r['Vendor'] == v]
    t_ships = len(v_rows)
    on_time_rate = sum(r['On_Time'] for r in v_rows) / t_ships if t_ships > 0 else 0
    avg_price = sum(r['Unit_Price'] for r in v_rows) / t_ships if t_ships > 0 else 0
    t_val = sum(r['Line_Item_Value'] for r in v_rows)
    
    truth["metrics"][v] = {
        "Total_Shipments": t_ships,
        "On_Time_Rate": round(on_time_rate, 4),
        "Avg_Unit_Price": round(avg_price, 4),
        "Total_Value": round(t_val, 2)
    }

with open('/var/lib/task_ground_truth/scorecard_truth.json', 'w') as f:
    json.dump(truth, f, indent=2)

# Write Excel File
wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Shipments"

headers = ['Vendor', 'Country', 'Shipment_Mode', 'Scheduled_Delivery', 'Actual_Delivery', 
           'Product_Group', 'Quantity', 'Unit_Price', 'Line_Item_Value', 'Freight_Cost', 'On_Time']
ws.append(headers)

# Format headers
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='0066CC', end_color='0066CC', fill_type='solid')
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill

for row in final_rows:
    ws.append([
        row['Vendor'], row['Country'], row['Shipment_Mode'], row['Scheduled_Delivery'],
        row['Actual_Delivery'], row['Product_Group'], row['Quantity'], row['Unit_Price'],
        row['Line_Item_Value'], row['Freight_Cost'], row['On_Time']
    ])

# Adjust columns
for col in ['A', 'B', 'C', 'D', 'E', 'F']:
    ws.column_dimensions[col].width = 18
for col in ['G', 'H', 'I', 'J', 'K']:
    ws.column_dimensions[col].width = 14

wb.save('/home/ga/Documents/supplier_shipments.xlsx')
print("Data preparation complete.")
PYEOF

python3 /tmp/prepare_data.py
chown ga:ga "$DATA_DIR/supplier_shipments.xlsx"

# Ensure WPS is not running
pkill -f "et" || true
pkill -f "wps" || true
sleep 2

# Launch WPS Spreadsheet
echo "Launching WPS Spreadsheet..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority et '$DATA_DIR/supplier_shipments.xlsx' &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "supplier_shipments"; then
        echo "WPS window detected"
        break
    fi
    sleep 1
done

sleep 3

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "supplier_shipments" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any potential popup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="