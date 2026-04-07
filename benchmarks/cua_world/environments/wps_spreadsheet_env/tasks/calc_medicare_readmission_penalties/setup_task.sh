#!/bin/bash
echo "=== Setting up calc_medicare_readmission_penalties task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

DATA_FILE="/home/ga/Documents/cms_readmissions.xlsx"

# Remove any existing file
rm -f "$DATA_FILE" 2>/dev/null || true

# Generate highly realistic CMS data with Python (to ensure it works offline and is exactly as described)
python3 << 'PYEOF'
import random
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()
ws = wb.active
ws.title = 'Readmissions'

headers = ['Facility_Name', 'State', 'Measure_Name', 'Number_of_Discharges', 'Excess_Readmission_Ratio']
ws.append(headers)

# Base data components
hospitals = [
    "GENERAL HOSPITAL", "MEMORIAL MEDICAL CENTER", "UNIVERSITY HOSPITAL", 
    "MERCY HEALTH", "VALLEY MEDICAL CENTER", "CITY HOSPITAL", "COUNTY GENERAL",
    "COMMUNITY HOSPITAL", "REGIONAL MEDICAL CENTER", "ST. JUDE MEDICAL",
    "GOOD SAMARITAN HOSPITAL", "BAPTIST HEALTH", "METHODIST HOSPITAL"
]
states = ["CA", "TX", "NY", "FL", "IL", "PA", "OH", "GA", "NC", "MI", "VA", "WA"]
measures = [
    "READM-30-AMI-HRRP", "READM-30-CABG-HRRP", "READM-30-COPD-HRRP", 
    "READM-30-HF-HRRP", "READM-30-HIP-KNEE-HRRP", "READM-30-PN-HRRP"
]

random.seed(1337) # Fixed seed for reproducibility

# Generate 2500 rows of data
for i in range(1, 2501):
    h = f"{random.choice(hospitals)} {random.randint(1, 500)}"
    s = random.choice(states)
    m = random.choice(measures)
    
    # CMS data frequently has "Not Available" for hospitals with too few cases
    if random.random() < 0.08:
        discharges = "Not Available"
        ratio = "Not Available"
    else:
        discharges = random.randint(25, 1200)
        # Ratio around 1.0 (some excessive, some acceptable)
        ratio = round(random.gauss(1.0, 0.08), 4)
        if ratio < 0.7: ratio = 0.7
        
    ws.append([h, s, m, discharges, ratio])

# Style headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9D9D9', end_color='D9D9D9', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill

ws.column_dimensions['A'].width = 35
ws.column_dimensions['B'].width = 8
ws.column_dimensions['C'].width = 25
ws.column_dimensions['D'].width = 22
ws.column_dimensions['E'].width = 25

wb.save('/home/ga/Documents/cms_readmissions.xlsx')
print(f"Created CMS HRRP dataset with 2500 records")
PYEOF

chown ga:ga "$DATA_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet
echo "Starting WPS Spreadsheet..."
su - ga -c "DISPLAY=:1 et '$DATA_FILE' &"
sleep 6

# Maximize the window for visibility
DISPLAY=:1 wmctrl -r "cms_readmissions" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "cms_readmissions" 2>/dev/null || true

sleep 2
# Clear any potential popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="