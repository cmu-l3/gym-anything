#!/bin/bash
echo "=== Setting up financial_consolidation_analysis task ==="

OUTPUT_FILE="/home/ga/Documents/meridian_holdings_consolidation.xlsx"

# Clean stale files
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/financial_consolidation_result.json 2>/dev/null || true
rm -f /tmp/financial_consolidation_gt.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/financial_consolidation_start_ts

# Data sources:
# - Trial balance figures: Based on SEC EDGAR 10-K filings for small-cap companies
#   in software/services (Alpha), distribution (Beta), and manufacturing (Gamma) sectors.
#   Revenue ranges and ratios calibrated to Census Bureau Annual Survey of Manufactures
#   and IRS SOI Corporate Income Tax Statistics, 2022-2023.
# - Intercompany transactions: Structured per ASC 810 consolidation guidance.
# - Prior year figures: Derived by applying industry growth rates from
#   BLS Quarterly Census of Employment and Wages (QCEW) 2023 to current year data.
#
# Create the multi-sheet starter workbook from real financial data
python3 << 'PYEOF'
import csv
import json
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side, numbers

wb = Workbook()

# Color scheme
header_font = Font(bold=True, size=11, color='FFFFFF')
header_fill = PatternFill(start_color='2F5496', end_color='2F5496', fill_type='solid')
section_font = Font(bold=True, size=11, color='2F5496')
section_fill = PatternFill(start_color='D6E4F0', end_color='D6E4F0', fill_type='solid')
currency_fmt = '#,##0'
thin_border = Border(
    bottom=Side(style='thin', color='B4C6E7')
)
total_border = Border(
    top=Side(style='double', color='2F5496'),
    bottom=Side(style='double', color='2F5496')
)

# Read trial balance data
tb_data = []
with open('/workspace/data/consolidation_trial_balances.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        tb_data.append(row)

# Read intercompany data
ic_data = []
with open('/workspace/data/consolidation_intercompany.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        ic_data.append(row)

# Read prior year data
py_data = []
with open('/workspace/data/consolidation_prior_year.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        py_data.append(row)

def create_subsidiary_sheet(wb, name, col_key, data):
    """Create a formatted subsidiary financial statement sheet."""
    ws = wb.create_sheet(title=name)

    # Title
    ws['A1'] = f'{name} - Financial Statements'
    ws['A1'].font = Font(bold=True, size=14, color='2F5496')
    ws.merge_cells('A1:B1')

    # Headers
    ws['A3'] = 'Account'
    ws['B3'] = 'Amount ($)'
    for cell in [ws['A3'], ws['B3']]:
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center')

    row = 4
    current_section = None
    for item in data:
        section = item['Section']
        if section != current_section:
            # Section header
            if current_section is not None:
                row += 1  # blank row between sections
            section_labels = {
                'Income': 'INCOME STATEMENT',
                'Assets': 'BALANCE SHEET - ASSETS',
                'Liabilities': 'BALANCE SHEET - LIABILITIES',
                'Equity': 'BALANCE SHEET - EQUITY'
            }
            ws.cell(row=row, column=1, value=section_labels.get(section, section))
            ws.cell(row=row, column=1).font = section_font
            ws.cell(row=row, column=1).fill = section_fill
            ws.cell(row=row, column=2).fill = section_fill
            current_section = section
            row += 1

        account = item['Account']
        amount = int(item[col_key])

        ws.cell(row=row, column=1, value=account)
        ws.cell(row=row, column=2, value=amount)
        ws.cell(row=row, column=2).number_format = currency_fmt
        ws.cell(row=row, column=2).alignment = Alignment(horizontal='right')

        # Bold for totals
        if account.startswith('Total') or account in ['Gross Profit', 'Operating Income',
                                                        'Income Before Tax', 'Net Income']:
            ws.cell(row=row, column=1).font = Font(bold=True)
            ws.cell(row=row, column=2).font = Font(bold=True)
            ws.cell(row=row, column=2).border = total_border
        else:
            ws.cell(row=row, column=2).border = thin_border

        row += 1

    ws.column_dimensions['A'].width = 35
    ws.column_dimensions['B'].width = 18
    return ws

# Create subsidiary sheets
for sub_name, col_key in [('Alpha_Inc', 'Alpha_Inc'), ('Beta_Corp', 'Beta_Corp'), ('Gamma_LLC', 'Gamma_LLC')]:
    create_subsidiary_sheet(wb, sub_name, col_key, tb_data)

# Remove default sheet
if 'Sheet' in wb.sheetnames:
    del wb['Sheet']

# Create Intercompany sheet
ws_ic = wb.create_sheet(title='Intercompany')
ws_ic['A1'] = 'Intercompany Transactions - For Elimination'
ws_ic['A1'].font = Font(bold=True, size=14, color='2F5496')
ws_ic.merge_cells('A1:F1')

ic_headers = ['From Entity', 'To Entity', 'Transaction Type', 'Revenue Elimination',
              'COGS Elimination', 'OpEx Elimination', 'AR Elimination', 'AP Elimination', 'Description']
for col, h in enumerate(ic_headers, 1):
    cell = ws_ic.cell(row=3, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center', wrap_text=True)

for i, row_data in enumerate(ic_data, 4):
    ws_ic.cell(row=i, column=1, value=row_data['From'])
    ws_ic.cell(row=i, column=2, value=row_data['To'])
    ws_ic.cell(row=i, column=3, value=row_data['Type'])
    for col, key in enumerate(['RevenueElim', 'COGSElim', 'OpExElim', 'ARElim', 'APElim'], 4):
        cell = ws_ic.cell(row=i, column=col, value=int(row_data[key]))
        cell.number_format = currency_fmt
    ws_ic.cell(row=i, column=9, value=row_data['Description'])

# Totals row for IC
total_row = len(ic_data) + 4
ws_ic.cell(row=total_row, column=3, value='TOTAL ELIMINATIONS')
ws_ic.cell(row=total_row, column=3).font = Font(bold=True)
for col in range(4, 9):
    cell = ws_ic.cell(row=total_row, column=col)
    col_letter = openpyxl.utils.get_column_letter(col)
    cell.value = f'=SUM({col_letter}4:{col_letter}{total_row-1})'
    cell.font = Font(bold=True)
    cell.number_format = currency_fmt
    cell.border = total_border

for col_idx, width in enumerate([16, 16, 18, 18, 16, 16, 16, 16, 45], 1):
    ws_ic.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

# Create Prior Year sheet
ws_py = wb.create_sheet(title='Prior_Year')
ws_py['A1'] = 'Prior Year Consolidated Financial Statements'
ws_py['A1'].font = Font(bold=True, size=14, color='2F5496')
ws_py.merge_cells('A1:B1')

ws_py['A3'] = 'Account'
ws_py['B3'] = 'Amount ($)'
for cell in [ws_py['A3'], ws_py['B3']]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

row = 4
current_section = None
for item in py_data:
    section = item['Section']
    if section != current_section:
        if current_section is not None:
            row += 1
        section_labels = {
            'Income': 'INCOME STATEMENT',
            'Assets': 'BALANCE SHEET - ASSETS',
            'Liabilities': 'BALANCE SHEET - LIABILITIES',
            'Equity': 'BALANCE SHEET - EQUITY'
        }
        ws_py.cell(row=row, column=1, value=section_labels.get(section, section))
        ws_py.cell(row=row, column=1).font = section_font
        ws_py.cell(row=row, column=1).fill = section_fill
        ws_py.cell(row=row, column=2).fill = section_fill
        current_section = section
        row += 1

    ws_py.cell(row=row, column=1, value=item['Account'])
    ws_py.cell(row=row, column=2, value=int(item['Amount']))
    ws_py.cell(row=row, column=2).number_format = currency_fmt
    ws_py.cell(row=row, column=2).alignment = Alignment(horizontal='right')

    if item['Account'].startswith('Total') or item['Account'] in ['Gross Profit', 'Operating Income',
                                                                     'Income Before Tax', 'Net Income']:
        ws_py.cell(row=row, column=1).font = Font(bold=True)
        ws_py.cell(row=row, column=2).font = Font(bold=True)
        ws_py.cell(row=row, column=2).border = total_border
    else:
        ws_py.cell(row=row, column=2).border = thin_border
    row += 1

ws_py.column_dimensions['A'].width = 35
ws_py.column_dimensions['B'].width = 18

# Save
wb.save('/home/ga/Documents/meridian_holdings_consolidation.xlsx')
print(f"Created consolidation workbook with sheets: {wb.sheetnames}")

# Save ground truth for verifier
gt = {
    "consolidated_revenue": 96500000,
    "consolidated_cogs": 56746000,
    "consolidated_gross_profit": 39754000,
    "consolidated_sga": 20000000,
    "consolidated_rd": 3850000,
    "consolidated_da": 3300000,
    "consolidated_operating_income": 12604000,
    "consolidated_interest": 1280000,
    "consolidated_ibt": 11324000,
    "consolidated_tax": 2831000,
    "consolidated_net_income": 8493000,
    "consolidated_cash": 15700000,
    "consolidated_ar": 17600000,
    "consolidated_inventory": 16800000,
    "consolidated_total_current_assets": 50100000,
    "consolidated_ppe": 37000000,
    "consolidated_intangibles": 9850000,
    "consolidated_total_assets": 96950000,
    "consolidated_ap": 10150000,
    "consolidated_st_debt": 7000000,
    "consolidated_total_current_liabilities": 17150000,
    "consolidated_lt_debt": 21600000,
    "consolidated_total_liabilities": 38750000,
    "consolidated_equity": 58200000,
    "ic_revenue_elimination": 5500000,
    "ic_cogs_elimination": 4000000,
    "ic_opex_elimination": 1500000,
    "ic_ar_elimination": 1250000,
    "ic_ap_elimination": 1250000,
    "current_ratio": 2.92,
    "quick_ratio": 1.94,
    "debt_to_equity": 0.666,
    "gross_margin_pct": 41.2,
    "operating_margin_pct": 13.06,
    "net_margin_pct": 8.80,
    "roe_pct": 14.59,
    "roa_pct": 8.76,
    "prior_year_revenue": 91800000,
    "prior_year_net_income": 7537000,
    "revenue_variance_pct": 5.12,
    "net_income_variance_pct": 12.68,
    "starter_sheets": ["Alpha_Inc", "Beta_Corp", "Gamma_LLC", "Intercompany", "Prior_Year"]
}
with open('/tmp/financial_consolidation_gt.json', 'w') as f:
    json.dump(gt, f)

PYEOF

# Ensure proper ownership
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
DISPLAY=:1 import -window root /tmp/financial_consolidation_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/financial_consolidation_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
