#!/bin/bash
echo "=== Setting up Accounts Receivable Aging Analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any existing files
rm -f /home/ga/Documents/ar_data.xlsx 2>/dev/null || true

# Generate realistic, deterministic dataset simulating Northwind Database exports
python3 << 'PYEOF'
import openpyxl
from openpyxl.styles import Font, PatternFill
from datetime import date, timedelta
import random

# Use a fixed seed to ensure deterministic data for the verifier
random.seed(1042)

wb = openpyxl.Workbook()
ws_cust = wb.active
ws_cust.title = "Customers"
ws_inv = wb.create_sheet("Invoices")
ws_pay = wb.create_sheet("Payments")

header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color="4F81BD", end_color="4F81BD", fill_type="solid")

def style_header(ws):
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill

# --- 1. Customers ---
ws_cust.append(["CustomerID", "CompanyName", "ContactName", "Country", "CreditLimit"])
companies = [
    "Alfreds Futterkiste", "Ana Trujillo Emparedados", "Antonio Moreno Taqueria", "Around the Horn",
    "Berglunds snabbkop", "Blauer See Delikatessen", "Blondesddsl pere et fils", "Bolido Comidas",
    "Bon app", "Bottom-Dollar Markets", "B's Beverages", "Cactus Comidas para llevar",
    "Centro comercial Moctezuma", "Chop-suey Chinese", "Comercio Mineiro", "Consolidated Holdings",
    "Drachenblut Delikatessen", "Du monde entier", "Eastern Connection", "Ernst Handel",
    "Familia Arquibaldo", "FISSA Fabrica Inter. Salchichas", "Folies gourmandes", "Folk och fa HB",
    "Frankenversand"
]
for i, comp in enumerate(companies, 1):
    ws_cust.append([f"CUST{i:03d}", comp, f"Contact {i}", random.choice(["USA", "UK", "Germany", "France", "Spain", "Brazil"]), random.choice([5000, 10000, 15000, 25000])])
style_header(ws_cust)
ws_cust.column_dimensions['B'].width = 30

# --- 2. Invoices ---
ws_inv.append(["InvoiceNo", "CustomerID", "InvoiceDate", "Amount", "PaymentTerms"])
invoices = []
start_date = date(2024, 1, 15)
for i in range(1, 101):
    inv_id = f"INV-{1000+i}"
    cust_id = f"CUST{random.randint(1, 25):03d}"
    inv_date = start_date + timedelta(days=random.randint(0, 320))
    amt = round(random.uniform(200.0, 8500.0), 2)
    terms = random.choice([15, 30, 45, 60])
    
    # Store date as excel date object for proper formatting
    ws_inv.append([inv_id, cust_id, inv_date, amt, terms])
    ws_inv.cell(row=i+1, column=3).number_format = 'YYYY-MM-DD'
    ws_inv.cell(row=i+1, column=4).number_format = '$#,##0.00'
    invoices.append({"id": inv_id, "cust": cust_id, "amt": amt, "date": inv_date})
style_header(ws_inv)
ws_inv.column_dimensions['C'].width = 15

# --- 3. Payments ---
ws_pay.append(["PaymentNo", "CustomerID", "PaymentDate", "Amount", "InvoiceRef"])
pay_idx = 1
for inv in invoices:
    # 75% chance an invoice has some payment
    if random.random() > 0.25 and pay_idx <= 75:
        pay_date = inv["date"] + timedelta(days=random.randint(10, 80))
        # 60% chance full payment, 40% partial
        amt = inv["amt"] if random.random() > 0.4 else round(inv["amt"] * random.uniform(0.3, 0.8), 2)
        
        ws_pay.append([f"PAY-{5000+pay_idx}", inv["cust"], pay_date, amt, inv["id"]])
        ws_pay.cell(row=pay_idx+1, column=3).number_format = 'YYYY-MM-DD'
        ws_pay.cell(row=pay_idx+1, column=4).number_format = '$#,##0.00'
        pay_idx += 1
        if pay_idx > 75:
            break
style_header(ws_pay)
ws_pay.column_dimensions['C'].width = 15

wb.save("/home/ga/Documents/ar_data.xlsx")
PYEOF

# Set proper ownership
chown ga:ga /home/ga/Documents/ar_data.xlsx

# Ensure WPS Spreadsheet starts in a clean state
pkill -x et 2>/dev/null || true
sleep 1

# Launch the application and load the dataset
echo "Launching WPS Spreadsheet..."
su - ga -c "DISPLAY=:1 /usr/bin/et /home/ga/Documents/ar_data.xlsx &"
sleep 6

# Wait for window, maximize, and focus
for i in {1..20}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "ar_data.xlsx" | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Dismiss any potential WPS dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="