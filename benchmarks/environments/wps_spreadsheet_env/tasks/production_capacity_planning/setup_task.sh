#!/bin/bash
echo "=== Setting up production_capacity_planning task ==="

OUTPUT_FILE="/home/ga/Documents/production_capacity_plan.xlsx"

# Clean stale files
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/production_capacity_result.json 2>/dev/null || true
rm -f /tmp/production_capacity_gt.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/production_capacity_start_ts

# Data sources:
# - Production line specs: Based on published manufacturing capacity benchmarks from
#   Census Bureau Annual Survey of Manufactures (ASM) and BLS Quarterly Census of
#   Employment and Wages for NAICS 332-336 (metal/machinery/electronics manufacturing).
# - Order volumes and pricing: Calibrated to producer price indices (PPI) for
#   fabricated metal products (BLS series WPU10) and machinery (WPU11), 2024.
# - Production calendar: Real January 2025 calendar with federal holidays.
#
# Create the multi-sheet starter workbook
python3 << 'PYEOF'
import csv
import json
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from datetime import datetime

wb = Workbook()

header_font = Font(bold=True, size=11, color='FFFFFF')
header_fill = PatternFill(start_color='548235', end_color='548235', fill_type='solid')
subheader_fill = PatternFill(start_color='E2EFDA', end_color='E2EFDA', fill_type='solid')
thin_border = Border(bottom=Side(style='thin', color='A9D18E'))

# === Sheet 1: Production Lines ===
ws = wb.active
ws.title = 'Production_Lines'
ws['A1'] = 'Production Line Specifications'
ws['A1'].font = Font(bold=True, size=14, color='548235')
ws.merge_cells('A1:G1')

headers = ['Line ID', 'Line Name', 'Max Units/Day', 'Products Supported', 'Shift Hours', 'Setup Time (hrs)', 'Cost/Hour ($)']
for col, h in enumerate(headers, 1):
    cell = ws.cell(row=3, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center', wrap_text=True)

with open('/workspace/data/production_lines.csv', 'r') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 4):
        ws.cell(row=i, column=1, value=row['Line_ID'])
        ws.cell(row=i, column=2, value=row['Line_Name'])
        ws.cell(row=i, column=3, value=int(row['Max_Units_Per_Day']))
        ws.cell(row=i, column=4, value=row['Products_Supported'])
        ws.cell(row=i, column=5, value=int(row['Shift_Hours']))
        ws.cell(row=i, column=6, value=float(row['Setup_Time_Hours']))
        ws.cell(row=i, column=7, value=float(row['Cost_Per_Hour']))
        ws.cell(row=i, column=7).number_format = '$#,##0'

for col_idx, width in enumerate([10, 22, 14, 45, 12, 16, 14], 1):
    ws.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

# === Sheet 2: Orders ===
ws2 = wb.create_sheet(title='Orders')
ws2['A1'] = 'Customer Orders - January 2025'
ws2['A1'].font = Font(bold=True, size=14, color='548235')
ws2.merge_cells('A1:H1')

order_headers = ['Order ID', 'Customer', 'Product', 'Quantity', 'Order Date', 'Due Date', 'Priority', 'Unit Revenue ($)']
for col, h in enumerate(order_headers, 1):
    cell = ws2.cell(row=3, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center', wrap_text=True)

with open('/workspace/data/production_orders.csv', 'r') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 4):
        ws2.cell(row=i, column=1, value=row['Order_ID'])
        ws2.cell(row=i, column=2, value=row['Customer'])
        ws2.cell(row=i, column=3, value=row['Product'])
        ws2.cell(row=i, column=4, value=int(row['Quantity']))
        ws2.cell(row=i, column=5, value=datetime.strptime(row['Order_Date'], '%Y-%m-%d'))
        ws2.cell(row=i, column=5).number_format = 'YYYY-MM-DD'
        ws2.cell(row=i, column=6, value=datetime.strptime(row['Due_Date'], '%Y-%m-%d'))
        ws2.cell(row=i, column=6).number_format = 'YYYY-MM-DD'
        ws2.cell(row=i, column=7, value=row['Priority'])
        ws2.cell(row=i, column=8, value=float(row['Unit_Revenue']))
        ws2.cell(row=i, column=8).number_format = '$#,##0.00'

        # Color-code priority
        prio = row['Priority']
        if prio == 'Critical':
            ws2.cell(row=i, column=7).fill = PatternFill(start_color='FF0000', end_color='FF0000', fill_type='solid')
            ws2.cell(row=i, column=7).font = Font(color='FFFFFF', bold=True)
        elif prio == 'High':
            ws2.cell(row=i, column=7).fill = PatternFill(start_color='FFC000', end_color='FFC000', fill_type='solid')

for col_idx, width in enumerate([12, 16, 12, 10, 12, 12, 10, 16], 1):
    ws2.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

# === Sheet 3: Calendar ===
ws3 = wb.create_sheet(title='Calendar')
ws3['A1'] = 'Production Calendar - January 2025'
ws3['A1'].font = Font(bold=True, size=14, color='548235')
ws3.merge_cells('A1:D1')

cal_headers = ['Date', 'Day of Week', 'Day Type', 'Notes']
for col, h in enumerate(cal_headers, 1):
    cell = ws3.cell(row=3, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

with open('/workspace/data/production_calendar.csv', 'r') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 4):
        dt = datetime.strptime(row['Date'], '%Y-%m-%d')
        ws3.cell(row=i, column=1, value=dt)
        ws3.cell(row=i, column=1).number_format = 'YYYY-MM-DD'
        ws3.cell(row=i, column=2, value=dt.strftime('%A'))
        ws3.cell(row=i, column=3, value=row['Day_Type'])
        ws3.cell(row=i, column=4, value=row['Notes'])

        if row['Day_Type'] != 'Working':
            for col in range(1, 5):
                ws3.cell(row=i, column=col).fill = PatternFill(start_color='F2DCDB', end_color='F2DCDB', fill_type='solid')

for col_idx, width in enumerate([12, 14, 14, 20], 1):
    ws3.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

wb.save('/home/ga/Documents/production_capacity_plan.xlsx')
print(f"Created production workbook with sheets: {wb.sheetnames}")

# Save ground truth
gt = {
    "total_orders": 15,
    "total_quantity": 21060,
    "working_days": {"week1": 5, "week2": 5, "week3": 4, "week4": 5},
    "total_working_days": 19,
    "num_lines": 4,
    "starter_sheets": ["Production_Lines", "Orders", "Calendar"]
}
with open('/tmp/production_capacity_gt.json', 'w') as f:
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
DISPLAY=:1 import -window root /tmp/production_capacity_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/production_capacity_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
