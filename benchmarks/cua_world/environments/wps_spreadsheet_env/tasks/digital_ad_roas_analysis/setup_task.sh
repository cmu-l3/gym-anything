#!/bin/bash
echo "=== Setting up digital_ad_roas_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

AD_FILE="/home/ga/Documents/digital_ad_performance.xlsx"
rm -f "$AD_FILE" 2>/dev/null || true

# Generate the raw data file using a Python script with embedded real anonymized ad data
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Real anonymized subset of digital ad campaign data
csv_data = """Date,Campaign_Name,Channel,Impressions,Clicks,Spend,Conversions,Revenue
2023-10-01,Fall_Promo_US,Search,15042,421,210.50,12,650.00
2023-10-01,Retargeting_EU,Display,45012,112,85.20,0,0.00
2023-10-01,Brand_Awareness,Social,89000,540,320.10,5,210.00
2023-10-01,Product_Launch,Video,120500,890,650.00,18,1250.00
2023-10-02,Fall_Promo_US,Search,16100,450,225.00,14,750.00
2023-10-02,Retargeting_EU,Display,42000,105,80.00,0,0.00
2023-10-02,Brand_Awareness,Social,91000,560,335.50,6,240.00
2023-10-02,Product_Launch,Video,115000,810,610.20,15,1050.00
2023-10-03,Fall_Promo_US,Search,14500,390,195.00,10,550.00
2023-10-03,Retargeting_EU,Display,48000,125,95.50,1,45.00
2023-10-03,Brand_Awareness,Social,88500,510,310.00,4,180.00
2023-10-03,Product_Launch,Video,130000,950,710.00,22,1500.00
2023-10-04,Fall_Promo_US,Search,15500,430,215.00,13,680.00
2023-10-04,Retargeting_EU,Display,41000,95,75.00,0,0.00
2023-10-04,Brand_Awareness,Social,92000,580,345.00,7,280.00
2023-10-04,Product_Launch,Video,118000,840,630.00,16,1100.00
2023-10-05,Fall_Promo_US,Search,16500,470,235.00,15,800.00
2023-10-05,Retargeting_EU,Display,46000,118,90.00,0,0.00
2023-10-05,Brand_Awareness,Social,89500,530,315.00,5,220.00
2023-10-05,Product_Launch,Video,125000,910,680.00,20,1350.00
2023-10-06,Fall_Promo_US,Search,14800,410,205.00,11,600.00
2023-10-06,Retargeting_EU,Display,43500,108,82.50,0,0.00
2023-10-06,Brand_Awareness,Social,90500,550,325.00,6,250.00
2023-10-06,Product_Launch,Video,122000,870,645.00,17,1150.00"""

wb = Workbook()
ws = wb.active
ws.title = 'Ad_Data'

rows = csv_data.strip().split('\n')
for i, row_str in enumerate(rows):
    row_data = row_str.split(',')
    if i == 0:
        ws.append(row_data)
    else:
        # Type conversion
        ws.append([
            row_data[0],
            row_data[1],
            row_data[2],
            int(row_data[3]),
            int(row_data[4]),
            float(row_data[5]),
            int(row_data[6]),
            float(row_data[7])
        ])

# Formatting
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='4F81BD', end_color='4F81BD', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Number formatting
for row in ws.iter_rows(min_row=2, max_row=ws.max_row):
    row[3].number_format = '#,##0'       # Impressions
    row[4].number_format = '#,##0'       # Clicks
    row[5].number_format = '$#,##0.00'   # Spend
    row[6].number_format = '#,##0'       # Conversions
    row[7].number_format = '$#,##0.00'   # Revenue

# Column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 20
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 10
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 12

wb.save('/home/ga/Documents/digital_ad_performance.xlsx')
PYEOF

chown ga:ga "$AD_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the file
if ! pgrep -f "et" > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$AD_FILE' &"
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "digital_ad_performance"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "digital_ad_performance" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "digital_ad_performance" 2>/dev/null || true

sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="