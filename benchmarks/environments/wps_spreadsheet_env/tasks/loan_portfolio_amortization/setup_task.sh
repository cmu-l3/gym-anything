#!/bin/bash
echo "=== Setting up loan_portfolio_amortization task ==="

OUTPUT_FILE="/home/ga/Documents/loan_portfolio_model.xlsx"

rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/loan_portfolio_result.json 2>/dev/null || true
rm -f /tmp/loan_portfolio_gt.json 2>/dev/null || true

date +%s > /tmp/loan_portfolio_start_ts

# Data sources:
# - SOFR rates: Federal Reserve Bank of New York, 30-Day Average SOFR
#   (FRED series SOFR30DAYAVG), Jan 2024 - Dec 2025.
#   Source: https://fred.stlouisfed.org/series/SOFR30DAYAVG
# - CRE loan terms: Typical commercial real estate loan structures per
#   Federal Reserve Senior Loan Officer Opinion Survey (SLOOS) and
#   Mortgage Bankers Association (MBA) Commercial/Multifamily Quarterly Databook.
# - Property NOI: Based on NCREIF Property Index (NPI) operating income
#   benchmarks for office, multifamily, retail, and industrial property types.

python3 << 'PYEOF'
import csv
import json
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from datetime import datetime

wb = Workbook()

header_font = Font(bold=True, size=10, color='FFFFFF')
header_fill = PatternFill(start_color='1F4E79', end_color='1F4E79', fill_type='solid')
note_fill = PatternFill(start_color='D6DCE4', end_color='D6DCE4', fill_type='solid')

# === Sheet 1: Loan Terms ===
ws = wb.active
ws.title = 'Loan_Terms'
ws['A1'] = 'Commercial Real Estate Loan Portfolio'
ws['A1'].font = Font(bold=True, size=14, color='1F4E79')
ws.merge_cells('A1:J1')

ws['A2'] = 'As of January 2025'
ws['A2'].font = Font(italic=True, size=10, color='808080')

headers = ['Loan ID', 'Borrower/Property', 'Loan Type', 'Original Principal ($)',
           'Annual Rate (%)', 'Term (Months)', 'Start Date', 'Payment Frequency',
           'Balloon (%)', 'Covenant Min DSCR']
for col, h in enumerate(headers, 1):
    cell = ws.cell(row=4, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center', wrap_text=True)

with open('/workspace/data/loan_portfolio.csv', 'r') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 5):
        ws.cell(row=i, column=1, value=row['Loan_ID'])
        ws.cell(row=i, column=2, value=row['Borrower'])
        ws.cell(row=i, column=3, value=row['Loan_Type'])
        ws.cell(row=i, column=4, value=int(row['Original_Principal']))
        ws.cell(row=i, column=4).number_format = '$#,##0'
        rate = float(row['Annual_Rate_Pct'])
        if rate == 0:
            ws.cell(row=i, column=5, value='Variable (see Rate_Curve)')
            ws.cell(row=i, column=5).font = Font(italic=True, color='C00000')
        else:
            ws.cell(row=i, column=5, value=rate / 100)
            ws.cell(row=i, column=5).number_format = '0.000%'
        ws.cell(row=i, column=6, value=int(row['Term_Months']))
        ws.cell(row=i, column=7, value=datetime.strptime(row['Start_Date'], '%Y-%m-%d'))
        ws.cell(row=i, column=7).number_format = 'YYYY-MM-DD'
        ws.cell(row=i, column=8, value=row['Payment_Frequency'])
        balloon = int(row['Balloon_Pct'])
        ws.cell(row=i, column=9, value=balloon / 100 if balloon > 0 else 0)
        ws.cell(row=i, column=9).number_format = '0%'
        ws.cell(row=i, column=10, value=float(row['Covenant_Min_DSCR']))
        ws.cell(row=i, column=10).number_format = '0.00'

# Notes section
ws.cell(row=12, column=1, value='Notes:')
ws.cell(row=12, column=1).font = Font(bold=True, size=10)
notes = [
    'LOAN-003: Balloon loan - 40% of original principal due at maturity',
    'LOAN-004: Variable rate = SOFR + 175bps (see Rate_Curve sheet)',
    'LOAN-006: Interest-only for full term; principal due at maturity',
    'DSCR = Net Operating Income / Annual Debt Service'
]
for idx, note in enumerate(notes):
    ws.cell(row=13 + idx, column=1, value=note)
    ws.cell(row=13 + idx, column=1).font = Font(size=9, italic=True, color='808080')

for col_idx, width in enumerate([12, 26, 18, 20, 16, 14, 14, 16, 12, 16], 1):
    ws.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

# === Sheet 2: Rate Curve ===
ws2 = wb.create_sheet(title='Rate_Curve')
ws2['A1'] = 'SOFR Forward Curve - For Variable Rate Loans'
ws2['A1'].font = Font(bold=True, size=14, color='1F4E79')
ws2.merge_cells('A1:D1')

ws2['A2'] = 'Source: CME SOFR futures, Federal Reserve H.15'
ws2['A2'].font = Font(italic=True, size=9, color='808080')

rc_headers = ['Date', 'SOFR Rate (%)', 'Spread (bps)', 'Effective Rate (%)']
for col, h in enumerate(rc_headers, 1):
    cell = ws2.cell(row=4, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

with open('/workspace/data/rate_curve.csv', 'r') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 5):
        ws2.cell(row=i, column=1, value=datetime.strptime(row['Date'], '%Y-%m-%d'))
        ws2.cell(row=i, column=1).number_format = 'YYYY-MM-DD'
        ws2.cell(row=i, column=2, value=float(row['SOFR_Rate']) / 100)
        ws2.cell(row=i, column=2).number_format = '0.00%'
        ws2.cell(row=i, column=3, value=int(row['Spread_bps']))
        ws2.cell(row=i, column=4, value=float(row['Effective_Rate']) / 100)
        ws2.cell(row=i, column=4).number_format = '0.00%'

for col_idx, width in enumerate([14, 14, 12, 16], 1):
    ws2.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

# === Sheet 3: Property NOI ===
ws3 = wb.create_sheet(title='Property_NOI')
ws3['A1'] = 'Property Net Operating Income (NOI)'
ws3['A1'].font = Font(bold=True, size=14, color='1F4E79')
ws3.merge_cells('A1:D1')

noi_headers = ['Loan ID', 'Property', 'Monthly NOI ($)', 'Annual NOI ($)']
for col, h in enumerate(noi_headers, 1):
    cell = ws3.cell(row=3, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

with open('/workspace/data/property_noi.csv', 'r') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 4):
        ws3.cell(row=i, column=1, value=row['Loan_ID'])
        ws3.cell(row=i, column=2, value=row['Property'])
        ws3.cell(row=i, column=3, value=int(row['Monthly_NOI']))
        ws3.cell(row=i, column=3).number_format = '$#,##0'
        ws3.cell(row=i, column=4, value=int(row['Annual_NOI']))
        ws3.cell(row=i, column=4).number_format = '$#,##0'

for col_idx, width in enumerate([12, 26, 16, 16], 1):
    ws3.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

wb.save('/home/ga/Documents/loan_portfolio_model.xlsx')
print(f"Created loan portfolio workbook with sheets: {wb.sheetnames}")

gt = {
    "num_loans": 6,
    "total_principal": 23800000,
    "loan_types": {"Fixed Rate Term": 3, "Variable Rate": 1, "Balloon": 1, "Interest Only": 1},
    "starter_sheets": ["Loan_Terms", "Rate_Curve", "Property_NOI"]
}
with open('/tmp/loan_portfolio_gt.json', 'w') as f:
    json.dump(gt, f)

PYEOF

chown ga:ga "$OUTPUT_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the file (pre-positioning principle)
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et '$OUTPUT_FILE' &"

# Wait for WPS window to appear
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "\.xlsx\|WPS Spreadsheets\|et"; then
        echo "WPS Spreadsheet window is ready"
        break
    fi
    sleep 2
done

# Take initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/loan_portfolio_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/loan_portfolio_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
