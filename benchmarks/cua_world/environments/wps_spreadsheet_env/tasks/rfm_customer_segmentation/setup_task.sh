#!/bin/bash
set -euo pipefail

echo "=== Setting up RFM Customer Segmentation Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

RFM_FILE="/home/ga/Documents/rfm_analysis.xlsx"
rm -f "$RFM_FILE" 2>/dev/null || true

# Generate the initial Excel file with real Online Retail data and scoring rules
python3 << 'PYEOF'
import datetime
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()

# --- 1. Customer_Data Sheet ---
ws_data = wb.active
ws_data.title = 'Customer_Data'
headers = ['CustomerID', 'LastPurchaseDate', 'TotalOrders', 'TotalSpent']
ws_data.append(headers)

# Real sampled data from UCI Online Retail Dataset (aggregated)
# UK customers, Nov-Dec 2011 cohort activity
real_customers = [
    (12346, '2011-01-18', 1, 77183.60), (12747, '2011-12-07', 103, 4196.01),
    (12748, '2011-12-09', 4596, 33719.73), (12749, '2011-12-06', 199, 4090.88),
    (12820, '2011-12-06', 59, 942.34), (12821, '2011-05-09', 6, 92.72),
    (12822, '2011-09-30', 46, 948.88), (12823, '2011-09-26', 5, 1759.50),
    (12824, '2011-10-11', 25, 397.12), (12826, '2011-12-07', 91, 1474.72),
    (12827, '2011-12-05', 25, 430.15), (12828, '2011-12-07', 56, 1018.71),
    (12829, '2011-01-11', 11, 273.00), (12830, '2011-11-03', 38, 6814.64),
    (12831, '2011-03-22', 9, 215.05), (12832, '2011-11-07', 27, 383.03),
    (12833, '2011-07-17', 24, 417.38), (12834, '2011-03-02', 18, 312.38),
    (12836, '2011-10-11', 175, 2612.86), (12837, '2011-06-19', 12, 134.10),
    (12838, '2011-11-07', 123, 683.13), (12839, '2011-12-07', 314, 5591.42),
    (12840, '2011-07-28', 113, 2726.66), (12841, '2011-12-05', 420, 4022.25),
    (12842, '2011-10-01', 34, 1118.99), (12843, '2011-10-06', 103, 1702.26),
    (12844, '2011-11-11', 52, 325.85), (12845, '2011-03-17', 27, 354.09),
    (12847, '2011-11-18', 91, 871.54), (12849, '2011-11-09', 51, 1050.89),
    (12851, '2011-09-06', 63, 135.18), (12852, '2011-02-17', 2, 0.00),
    (12853, '2011-07-26', 82, 1957.10), (12854, '2011-09-22', 119, 1353.68),
    (12855, '2011-03-02', 3, 38.10), (12856, '2011-12-03', 225, 2861.36),
    (12857, '2011-09-29', 61, 1269.41), (12863, '2011-10-19', 45, 608.82),
    (12864, '2011-07-28', 3, 147.16), (12865, '2011-11-14', 103, 2033.43)
]

for row in real_customers:
    dt = datetime.datetime.strptime(row[1], "%Y-%m-%d").date()
    ws_data.append([row[0], dt, row[2], row[3]])

for row in ws_data.iter_rows(min_row=2, max_row=ws_data.max_row, min_col=2, max_col=2):
    for cell in row:
        cell.number_format = 'YYYY-MM-DD'
        
for row in ws_data.iter_rows(min_row=2, max_row=ws_data.max_row, min_col=4, max_col=4):
    for cell in row:
        cell.number_format = '£#,##0.00'

# --- 2. Scoring_Rules Sheet ---
ws_rules = wb.create_sheet(title="Scoring_Rules")
ws_rules.append(["Recency Threshold", "R Score", "", "Freq Threshold", "F Score", "", "Monetary Threshold", "M Score"])
rules = [
    [0, 4, "", 1, 1, "", 0, 1],
    [31, 3, "", 10, 2, "", 200, 2],
    [91, 2, "", 50, 3, "", 1000, 3],
    [181, 1, "", 100, 4, "", 3000, 4]
]
for r in rules:
    ws_rules.append(r)

# --- 3. Segment_Mapping Sheet ---
ws_mapping = wb.create_sheet(title="Segment_Mapping")
ws_mapping.append(["RFM Score", "Segment Name"])

def get_segment(r, f, m):
    if r in [4,3] and f in [4,3] and m in [4,3]: return "Champions"
    if r in [4,3] and f in [2,1]: return "Recent Customers"
    if r in [2] and f in [4,3,2]: return "At Risk"
    if r in [2,1] and f in [1]: return "Lost"
    if r in [1] and f in [4,3,2]: return "Hibernating"
    return "Loyal Customers"

for r in [1,2,3,4]:
    for f in [1,2,3,4]:
        for m in [1,2,3,4]:
            score = r*100 + f*10 + m
            ws_mapping.append([score, get_segment(r, f, m)])

# Formatting
header_fill = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')
header_font = Font(bold=True, color="FFFFFF")

for ws in wb.worksheets:
    for cell in ws[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal='center')
    for col in ws.columns:
        ws.column_dimensions[col[0].column_letter].width = 15

wb.save('/home/ga/Documents/rfm_analysis.xlsx')
PYEOF

chown ga:ga "$RFM_FILE"

# Start WPS Spreadsheet
if ! pgrep -x "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$RFM_FILE' &"
    sleep 6
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "rfm_analysis"; then
        echo "WPS Spreadsheet window detected"
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "rfm_analysis" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "rfm_analysis" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="