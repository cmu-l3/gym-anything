#!/bin/bash
echo "=== Setting up budget_variance_dashboard task ==="

OUTPUT_FILE="/home/ga/Documents/budget_variance_analysis.xlsx"

rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/budget_variance_result.json 2>/dev/null || true
rm -f /tmp/budget_variance_gt.json 2>/dev/null || true

date +%s > /tmp/budget_variance_start_ts

# Data sources:
# - Budget structure: Based on typical mid-size technology company cost center
#   allocation per AICPA Management Accounting Practice Statement.
# - Expense categories and ratios: Calibrated to BLS QCEW industry averages
#   for NAICS 54 (Professional, Scientific, and Technical Services), 2024.
# - Rent figures: Based on CBRE North America Office Occupier Sentiment Survey,
#   average office rent per square foot for Class A space, 2024.

python3 << 'PYEOF'
import csv
import json
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

wb = Workbook()

header_font = Font(bold=True, size=10, color='FFFFFF')
header_fill = PatternFill(start_color='BF8F00', end_color='BF8F00', fill_type='solid')
cc_fill = PatternFill(start_color='FFF2CC', end_color='FFF2CC', fill_type='solid')
months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

def create_data_sheet(wb, title, csv_path, is_first=False):
    if is_first:
        ws = wb.active
        ws.title = title
    else:
        ws = wb.create_sheet(title=title)

    ws['A1'] = f'{title} - FY 2024'
    ws['A1'].font = Font(bold=True, size=14, color='BF8F00')
    ws.merge_cells('A1:O1')

    headers = ['Cost Center', 'Expense Category', 'Type'] + months
    for col, h in enumerate(headers, 1):
        cell = ws.cell(row=3, column=col, value=h)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center', wrap_text=True)

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        prev_cc = None
        row_num = 4
        for row in reader:
            cc = row['Cost_Center']
            if cc != prev_cc and prev_cc is not None:
                # Subtotal row for previous cost center
                ws.cell(row=row_num, column=1, value=f'{prev_cc} Total')
                ws.cell(row=row_num, column=1).font = Font(bold=True, size=10)
                ws.cell(row=row_num, column=1).fill = cc_fill
                for col in range(2, 16):
                    ws.cell(row=row_num, column=col).fill = cc_fill
                # Sum formulas for each month
                start_row = None
                for r in range(4, row_num):
                    if ws.cell(row=r, column=1).value == prev_cc or (ws.cell(row=r, column=1).value and ws.cell(row=r, column=1).value.startswith(prev_cc.split(' ')[0]) and 'Total' not in str(ws.cell(row=r, column=1).value)):
                        if start_row is None:
                            start_row = r
                # Just leave it as visual separator
                row_num += 1
                prev_cc = cc

            if prev_cc is None:
                prev_cc = cc

            ws.cell(row=row_num, column=1, value=cc)
            ws.cell(row=row_num, column=2, value=row['Category'])
            ws.cell(row=row_num, column=3, value=row['Type'])

            for m_idx, m in enumerate(months):
                val = int(row[m])
                cell = ws.cell(row=row_num, column=4 + m_idx, value=val)
                cell.number_format = '#,##0'

            row_num += 1

        # Final subtotal
        if prev_cc:
            ws.cell(row=row_num, column=1, value=f'{prev_cc} Total')
            ws.cell(row=row_num, column=1).font = Font(bold=True)
            ws.cell(row=row_num, column=1).fill = cc_fill
            for col in range(2, 16):
                ws.cell(row=row_num, column=col).fill = cc_fill

    ws.column_dimensions['A'].width = 24
    ws.column_dimensions['B'].width = 22
    ws.column_dimensions['C'].width = 10
    for i in range(4, 16):
        ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = 11

    return ws

create_data_sheet(wb, 'Budget', '/workspace/data/budget_by_costcenter.csv', is_first=True)
create_data_sheet(wb, 'Actuals', '/workspace/data/actuals_by_costcenter.csv')

wb.save('/home/ga/Documents/budget_variance_analysis.xlsx')
print(f"Created budget workbook with sheets: {wb.sheetnames}")

gt = {
    "cost_centers": 8,
    "line_items": 28,
    "months": 12,
    "starter_sheets": ["Budget", "Actuals"]
}
with open('/tmp/budget_variance_gt.json', 'w') as f:
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
DISPLAY=:1 import -window root /tmp/budget_variance_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/budget_variance_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
