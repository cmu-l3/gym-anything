#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Forensic Transaction Audit Task (Chicago Vendor Payments) ==="

echo $(date +%s) > /tmp/forensic_transaction_audit_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

LEDGER_PATH="$WORKSPACE_DIR/chicago_vendor_payments.xlsx"

cat > /tmp/create_chicago_ledger.py << 'PYEOF'
#!/usr/bin/env python3
"""
Generate a Chicago Vendor Payments dataset based on real records from the
City of Chicago Open Data Portal - Vendor Payments (data.cityofchicago.org).

Columns: voucher_number, amount, check_date, department_name, contract_number, vendor_name
"""
import sys
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
from datetime import datetime
import random

random.seed(42)

wb = Workbook()
ws = wb.active
ws.title = "Vendor Payments"

# Header styling
header_fill = PatternFill(start_color="002060", end_color="002060", fill_type="solid")
header_font = Font(bold=True, size=11, color="FFFFFF")

headers = ["voucher_number", "amount", "check_date", "department_name", "contract_number", "vendor_name"]
for col_idx, header in enumerate(headers, 1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# ============================================================================
# REAL records from City of Chicago Open Data Portal
# ============================================================================
real_records = [
    ("PV81248102104", 175.00, "12/18/2024", "", "DV", "THOMAS HEITZMAN"),
    ("CVIP255012346", 15628.03, "12/15/2025", "DEPARTMENT OF FAMILY AND SUPPORT SERVICES", "230663", "MCDERMOTT CENTER"),
    ("CVIP244117202", 69.85, "03/27/2025", "", "241821", "CHRISTIAN COMMUNITY HEALTH CENTER"),
    ("PVCI25CI704025", 910.10, "12/23/2025", "DEPARTMENT OF FLEET AND FACILITY MANAGEMENT", "192525", "ODP BUSINESS SOLUTIONS LLC"),
    ("PV27252766021", 474.22, "03/18/2025", "", "DV", "WALMART CLAIMS SERVICES INC"),
    ("PV39243950790", 1130.00, "12/20/2024", "", "DV", "HOWARD ROBERTA MARIE"),
    ("CVIP242300264", 10584.39, "03/27/2025", "", "236555", "CHICAGO CONVENTION & TOURISM BUREAU INC"),
    ("PVCI25CI404505", 147093.28, "12/19/2025", "CHICAGO DEPARTMENT OF AVIATION", "129570", "K2 INTELLIGENCE LLC"),
]

# ============================================================================
# Additional realistic Chicago vendor payment records
# ============================================================================

departments = [
    "DEPARTMENT OF FAMILY AND SUPPORT SERVICES",
    "CHICAGO DEPARTMENT OF PUBLIC HEALTH",
    "CHICAGO DEPARTMENT OF AVIATION",
    "CHICAGO DEPARTMENT OF TRANSPORTATION",
    "DEPARTMENT OF FLEET AND FACILITY MANAGEMENT",
    "CHICAGO PUBLIC LIBRARY",
    "OFFICE OF EMERGENCY MANAGEMENT",
    "DEPARTMENT OF CULTURAL AFFAIRS",
    "DEPARTMENT OF BUILDINGS",
    "DEPARTMENT OF WATER MANAGEMENT",
    "DEPARTMENT OF STREETS AND SANITATION",
    "CHICAGO FIRE DEPARTMENT",
    "CHICAGO POLICE DEPARTMENT",
    "",  # blank department (direct vouchers)
]

vendors = [
    "AMAZON CAPITAL SERVICES INC",
    "CDW GOVERNMENT LLC",
    "DELL TECHNOLOGIES INC",
    "GRAINGER INC",
    "HOME DEPOT USA INC",
    "OFFICE DEPOT INC",
    "STAPLES CONTRACT AND COMMERCIAL INC",
    "UNITED PARCEL SERVICE INC",
    "FEDEX CORPORATE SERVICES INC",
    "AT&T CORP",
    "VERIZON WIRELESS",
    "COMCAST CABLE COMMUNICATIONS LLC",
    "CONSTELLATION NEWENERGY INC",
    "PEOPLES GAS LIGHT & COKE CO",
    "METROPOLITAN WATER RECLAMATION DISTRICT",
    "CINTAS CORPORATION",
    "UNIFIRST CORPORATION",
    "ARAMARK UNIFORM SERVICES",
    "CLARK CONSTRUCTION GROUP LLC",
    "WALSH CONSTRUCTION CO",
    "KENNY CONSTRUCTION CO",
    "JAMES MCHUGH CONSTRUCTION CO",
    "TURNER CONSTRUCTION CO",
    "F H PASCHEN SN NIELSEN",
    "ALDRIDGE ELECTRIC INC",
    "INTERLAKE MECALUX INC",
    "MOTOROLA SOLUTIONS INC",
    "AXON ENTERPRISE INC",
    "TYLER TECHNOLOGIES INC",
    "CONDUENT STATE AND LOCAL SOLUTIONS",
    "DELOITTE CONSULTING LLP",
    "KPMG LLP",
    "ERNST & YOUNG LLP",
    "PRICEWATERHOUSECOOPERS LLP",
    "JENNER & BLOCK LLP",
    "KIRKLAND & ELLIS LLP",
    "MAYER BROWN LLP",
    "SIDLEY AUSTIN LLP",
    "CHICAGO TRANSIT AUTHORITY",
    "METRA COMMUTER RAIL",
    "PACE SUBURBAN BUS SERVICE",
    "GREATER CHICAGO FOOD DEPOSITORY",
    "HEARTLAND ALLIANCE",
    "CATHOLIC CHARITIES OF THE ARCHDIOCESE",
    "SALVATION ARMY",
    "YMCA OF METROPOLITAN CHICAGO",
    "LURIE CHILDREN'S HOSPITAL",
    "RUSH UNIVERSITY MEDICAL CENTER",
    "NORTHWESTERN MEMORIAL HOSPITAL",
    "UNIVERSITY OF CHICAGO MEDICINE",
    "ADVOCATE HEALTH CARE",
    "SINAI HEALTH SYSTEM",
    "COOK COUNTY HEALTH",
    "CHICAGO HOUSING AUTHORITY",
    "METROPOLITAN PLANNING COUNCIL",
    "AECOM TECHNICAL SERVICES",
    "JACOBS ENGINEERING GROUP",
    "WSP USA INC",
    "HDR ENGINEERING INC",
    "PARSONS TRANSPORTATION GROUP",
    "LAKESHORE RECYCLING SYSTEMS LLC",
    "WASTE MANAGEMENT INC",
    "REPUBLIC SERVICES INC",
    "ELGIN SWEEPING SERVICES INC",
    "OZINGA READY MIX CONCRETE INC",
    "VULCAN MATERIALS COMPANY",
    "ILLINOIS CENTRAL RAILROAD",
    "ALSIP TRUCKING INC",
    "MIDWEST FENCE CORPORATION",
    "RELIABLE FIRE EQUIPMENT CO",
    "GLOBAL FIRE EQUIPMENT INC",
    "WENTWORTH TIRE SERVICE",
    "RUSH TRUCK CENTERS",
    "STANDARD EQUIPMENT CO",
    "JX ENTERPRISES INC",
    "HAVEY COMMUNICATIONS INC",
    "JOHNSON CONTROLS INC",
    "SIEMENS INDUSTRY INC",
    "HONEYWELL INTERNATIONAL INC",
    "SCHNEIDER ELECTRIC USA INC",
    "TRANE US INC",
    "CARRIER GLOBAL CORP",
]

# Voucher number prefixes matching real Chicago patterns
def gen_voucher():
    prefix = random.choice(["PV", "CVIP", "PVCI", "PV"])
    if prefix == "PV":
        return f"PV{random.randint(10, 99)}{random.randint(240000000, 259999999)}"
    elif prefix == "CVIP":
        return f"CVIP{random.randint(240, 259)}{random.randint(100000, 999999)}"
    else:
        dept_code = random.choice(["CI", "FD", "PD", "AV", "WM", "ST", "FL"])
        return f"PVCI25{dept_code}{random.randint(100000, 999999)}"

def gen_contract():
    if random.random() < 0.35:
        return "DV"
    else:
        return str(random.randint(100000, 299999))

def gen_date_2024():
    month = random.randint(1, 12)
    if month in [1, 3, 5, 7, 8, 10, 12]:
        day = random.randint(1, 28)
    elif month == 2:
        day = random.randint(1, 28)
    else:
        day = random.randint(1, 28)
    return f"{month:02d}/{day:02d}/2024"

def gen_amount():
    """Generate realistic government payment amounts."""
    r = random.random()
    if r < 0.25:
        return round(random.uniform(50, 500), 2)
    elif r < 0.50:
        return round(random.uniform(500, 5000), 2)
    elif r < 0.75:
        return round(random.uniform(5000, 50000), 2)
    elif r < 0.92:
        return round(random.uniform(50000, 200000), 2)
    else:
        return round(random.uniform(200000, 500000), 2)

# Generate ~192 additional records to reach ~200 total
additional_records = []
for _ in range(192):
    voucher = gen_voucher()
    amount = gen_amount()
    check_date = gen_date_2024()
    dept = random.choice(departments)
    contract = gen_contract()
    vendor = random.choice(vendors)
    additional_records.append((voucher, amount, check_date, dept, contract, vendor))

# Combine all records
all_records = real_records + additional_records

# Shuffle to mix real and generated
random.shuffle(all_records)

# Write data rows
for row_idx, record in enumerate(all_records, 2):
    voucher, amount, check_date, dept, contract, vendor = record
    ws.cell(row=row_idx, column=1, value=voucher)
    cell = ws.cell(row=row_idx, column=2, value=amount)
    cell.number_format = '#,##0.00'
    ws.cell(row=row_idx, column=3, value=check_date)
    ws.cell(row=row_idx, column=4, value=dept)
    ws.cell(row=row_idx, column=5, value=contract)
    ws.cell(row=row_idx, column=6, value=vendor)

# Adjust column widths
ws.column_dimensions['A'].width = 22
ws.column_dimensions['B'].width = 16
ws.column_dimensions['C'].width = 14
ws.column_dimensions['D'].width = 48
ws.column_dimensions['E'].width = 16
ws.column_dimensions['F'].width = 42

# Add data source info sheet
info = wb.create_sheet("Data Source")
info['A1'] = "City of Chicago Open Data Portal - Vendor Payments"
info['A1'].font = Font(bold=True, size=14)
info['A2'] = "Source: data.cityofchicago.org"
info['A3'] = f"Total Records: {len(all_records)}"
info['A4'] = f"Total Payment Amount: ${sum(r[1] for r in all_records):,.2f}"
info['A6'] = "COLUMNS:"
info['A6'].font = Font(bold=True)
info['A7'] = "voucher_number - Unique payment voucher identifier"
info['A8'] = "amount - Payment amount in USD"
info['A9'] = "check_date - Date payment was issued"
info['A10'] = "department_name - City department (blank for direct vouchers)"
info['A11'] = "contract_number - Contract ID or 'DV' for direct vouchers"
info['A12'] = "vendor_name - Payee / vendor name"
info['A14'] = "SCENARIO: The municipal Inspector General's office has obtained this"
info['A15'] = "vendor payment extract and requires a comprehensive forensic analysis."

wb.save(sys.argv[1])
print(f"Chicago vendor payments ledger created with {len(all_records)} records")
PYEOF

chmod +x /tmp/create_chicago_ledger.py
python3 /tmp/create_chicago_ledger.py "$LEDGER_PATH"
chown ga:ga "$LEDGER_PATH"

echo "Chicago vendor payments ledger created at: $LEDGER_PATH"

# Launch ONLYOFFICE with the ledger
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$LEDGER_PATH' > /tmp/onlyoffice_forensic_task.log 2>&1 &"

if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_forensic_task.log || true
fi

if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

protect_onlyoffice_from_oom

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

focus_onlyoffice_window

su - ga -c "DISPLAY=:1 import -window root /tmp/forensic_transaction_audit_setup_screenshot.png" || true

echo "=== Forensic Transaction Audit Task Setup Complete ==="
