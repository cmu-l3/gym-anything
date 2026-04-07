#!/bin/bash
echo "=== Setting up analyze_er_triage_compliance task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

ED_DATA_FILE="/home/ga/Documents/ed_encounters_august.xlsx"
rm -f "$ED_DATA_FILE" 2>/dev/null || true

# Generate highly realistic clinical dataset matching ED throughput distributions
python3 << 'PYEOF'
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
from datetime import datetime, timedelta
import random

wb = openpyxl.Workbook()
ws = wb.active
ws.title = 'Encounters'

headers = ['Encounter_ID', 'Arrival_Time', 'Triage_Time', 'Provider_Seen_Time', 'Discharge_Time', 'ESI_Level']
ws.append(headers)

start_date = datetime(2024, 8, 1, 0, 0, 0)
random.seed(42)  # For reproducibility

# Generate 450 realistically distributed encounters
for i in range(1, 451):
    # Clustered arrivals
    arr_time = start_date + timedelta(minutes=random.randint(0, 30*24*60))
    
    # Triage is usually fast (2 to 25 mins)
    tri_time = arr_time + timedelta(minutes=random.randint(2, 25))
    
    # ESI Distribution (1 is rare/critical, 3 is most common)
    esi = random.choices([1, 2, 3, 4, 5], weights=[2, 15, 50, 25, 8])[0]
    
    # Wait times scale inversely with acuity (with some random variance to force breaches)
    if esi == 1:
        wait_mins = random.randint(0, 15)
    elif esi == 2:
        wait_mins = random.randint(10, 85)
    elif esi == 3:
        wait_mins = random.randint(30, 180)
    elif esi == 4:
        wait_mins = random.randint(45, 240)
    else:
        wait_mins = random.randint(60, 300)
        
    prov_time = arr_time + timedelta(minutes=wait_mins)
    
    # Length of Stay (LOS) scales proportionally with acuity severity
    if esi <= 2:
        los_mins = random.randint(180, 720) # 3-12 hrs
    elif esi == 3:
        los_mins = random.randint(120, 480) # 2-8 hrs
    else:
        los_mins = random.randint(60, 240)  # 1-4 hrs
        
    dis_time = arr_time + timedelta(minutes=los_mins)
    
    ws.append([
        f"ENC{10000+i}",
        arr_time.strftime("%Y-%m-%d %H:%M:%S"),
        tri_time.strftime("%Y-%m-%d %H:%M:%S"),
        prov_time.strftime("%Y-%m-%d %H:%M:%S"),
        dis_time.strftime("%Y-%m-%d %H:%M:%S"),
        esi
    ])

# Formatting Headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Adjust columns
for col in ['A', 'B', 'C', 'D', 'E']:
    ws.column_dimensions[col].width = 22
ws.column_dimensions['F'].width = 12

wb.save('/home/ga/Documents/ed_encounters_august.xlsx')
print(f"Generated realistic ED dataset with {ws.max_row - 1} records.")
PYEOF

chown ga:ga "$ED_DATA_FILE" 2>/dev/null || true

# Start WPS Spreadsheet to save agent time
if ! pgrep -x "et" > /dev/null 2>&1; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$ED_DATA_FILE' &"
    sleep 8
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="