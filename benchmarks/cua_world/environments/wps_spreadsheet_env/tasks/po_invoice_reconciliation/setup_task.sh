#!/bin/bash
set -e
echo "=== Setting up PO Invoice Reconciliation task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Documents
sudo mkdir -p /var/lib/ground_truth

# Generate the workbook and ground truth data using a robust Python script
python3 << 'PYEOF'
import sqlite3
import urllib.request
import openpyxl
from openpyxl.styles import Font, PatternFill
import random
import json
import os

db_path = "/tmp/northwind.db"
# Try downloading Northwind database for real data
if not os.path.exists(db_path):
    try:
        urllib.request.urlretrieve("https://github.com/jpwhite3/northwind-SQLite3/raw/main/dist/northwind.db", db_path)
    except Exception as e:
        print(f"Failed to download DB: {e}")

# Default realistic data if DB is unavailable
vendors = ["Exotic Liquids", "Tokyo Traders", "Pavlova, Ltd.", "Specialty Biscuits, Ltd.",
           "PB Knäckebröd AB", "Refrescos Americanas LTDA", "Leka Trading", "Lyngbys Fiske",
           "Zaanse Snoepfabriek", "Karkki Oy"]
products = ["Chai", "Chang", "Aniseed Syrup", "Chef Anton's Cajun Seasoning",
            "Grandma's Boysenberry Spread", "Uncle Bob's Organic Dried Pears",
            "Northwoods Cranberry Sauce", "Mishi Kobe Niku", "Ikura", "Queso Cabrales"]

try:
    if os.path.exists(db_path):
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("SELECT CompanyName FROM Suppliers")
        db_vendors = [r[0] for r in c.fetchall()]
        if len(db_vendors) > 5: vendors = db_vendors
        c.execute("SELECT ProductName FROM Products")
        db_prods = [r[0] for r in c.fetchall()]
        if len(db_prods) > 5: products = db_prods
except Exception as e:
    print(f"Using fallback data due to DB error: {e}")

random.seed(42) # Ensure reproducible task generation

# 1. Generate Purchase Orders
pos = []
for i in range(50):
    po_num = f"PO-10{i:02d}"
    vendor = random.choice(vendors)
    desc = random.choice(products)
    date = f"2023-10-{random.randint(1,28):02d}"
    amt = round(random.uniform(500.0, 5000.0), 2)
    status = random.choice(["Open", "Closed"])
    pos.append({"po": po_num, "vendor": vendor, "desc": desc, "date": date, "amt": amt, "status": status})

# 2. Generate Invoices
invoices = []
gt = {
    'matched_count': 0, 
    'unmatched_count': 0, 
    'review_count': 0, 
    'total_variance': 0.0, 
    'total_expected': 0.0, 
    'total_invoiced': 0.0
}

# 40 exact matches
for i in range(40):
    po = pos[i]
    inv_no = f"INV-50{i:02d}"
    invoices.append({"inv": inv_no, "vendor": po["vendor"], "date": po["date"], "amt": po["amt"], "po_ref": po["po"], "terms": "Net 30"})
    gt['matched_count'] += 1
    gt['total_expected'] += po["amt"]
    gt['total_invoiced'] += po["amt"]

# 10 matches with variance
for i in range(40, 50):
    po = pos[i]
    inv_no = f"INV-50{i:02d}"
    
    # 5 with small variance (<5%), 5 with large variance (>5%)
    if i < 45:
        var_pct = random.uniform(0.01, 0.04)
    else:
        var_pct = random.uniform(0.06, 0.15)
        
    multiplier = 1 + (var_pct if random.random() > 0.5 else -var_pct)
    inv_amt = round(po["amt"] * multiplier, 2)
    
    invoices.append({"inv": inv_no, "vendor": po["vendor"], "date": po["date"], "amt": inv_amt, "po_ref": po["po"], "terms": "Net 30"})
    
    gt['matched_count'] += 1
    gt['total_expected'] += po["amt"]
    gt['total_invoiced'] += inv_amt
    
    var = inv_amt - po["amt"]
    gt['total_variance'] += var
    
    if abs(var / po["amt"]) > 0.05:
        gt['review_count'] += 1

# 5 unmatched invoices
for i in range(5):
    inv_no = f"INV-60{i:02d}"
    vendor = random.choice(vendors)
    amt = round(random.uniform(500.0, 5000.0), 2)
    invoices.append({"inv": inv_no, "vendor": vendor, "date": "2023-11-01", "amt": amt, "po_ref": f"PO-999{i}", "terms": "Net 30"})
    gt['unmatched_count'] += 1
    gt['total_invoiced'] += amt

# Shuffle invoices
random.shuffle(invoices)

# 3. Create Workbook
wb = openpyxl.Workbook()

# PurchaseOrders Sheet
ws_po = wb.active
ws_po.title = "PurchaseOrders"
headers_po = ["PO_Number", "Vendor", "Description", "OrderDate", "ExpectedAmount", "Status"]
ws_po.append(headers_po)
for cell in ws_po[1]: 
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color='DDEBF7', end_color='DDEBF7', fill_type='solid')

for p in pos:
    ws_po.append([p["po"], p["vendor"], p["desc"], p["date"], p["amt"], p["status"]])

# Format PO amounts
for row in ws_po.iter_rows(min_row=2, min_col=5, max_col=5):
    for cell in row: cell.number_format = '$#,##0.00'

# Invoices Sheet
ws_inv = wb.create_sheet("Invoices")
headers_inv = ["InvoiceNo", "Vendor", "InvoiceDate", "InvoiceAmount", "PO_Reference", "PaymentTerms"]
ws_inv.append(headers_inv)
for cell in ws_inv[1]: 
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color='E2EFDA', end_color='E2EFDA', fill_type='solid')

for inv in invoices:
    ws_inv.append([inv["inv"], inv["vendor"], inv["date"], inv["amt"], inv["po_ref"], inv["terms"]])

# Format Invoice amounts
for row in ws_inv.iter_rows(min_row=2, min_col=4, max_col=4):
    for cell in row: cell.number_format = '$#,##0.00'

# Adjust column widths
for ws in [ws_po, ws_inv]:
    for col in ['A', 'B', 'C', 'D', 'E', 'F']:
        ws.column_dimensions[col].width = 15
    ws.column_dimensions['B'].width = 30
    if ws.title == "PurchaseOrders":
        ws.column_dimensions['C'].width = 35

# Save Excel
file_path = '/home/ga/Documents/PO_Reconciliation.xlsx'
wb.save(file_path)

# Save Ground Truth
with open('/var/lib/ground_truth/po_reconciliation_gt.json', 'w') as f:
    json.dump(gt, f)

print(f"Generated {file_path} successfully.")
PYEOF

# Set proper permissions
chown ga:ga /home/ga/Documents/PO_Reconciliation.xlsx
chmod 700 /var/lib/ground_truth
chmod 600 /var/lib/ground_truth/po_reconciliation_gt.json

# Kill any existing WPS processes
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 2

# Launch WPS Spreadsheet with the file
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et /home/ga/Documents/PO_Reconciliation.xlsx &"
sleep 8

# Dismiss any startup dialogs
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Escape" 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="