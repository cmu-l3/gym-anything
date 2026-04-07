#!/bin/bash
echo "=== Setting up wind_turbine_performance_analysis task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

SCADA_FILE="/home/ga/Documents/wind_scada_2022.xlsx"
rm -f "$SCADA_FILE" 2>/dev/null || true

# Download real Wind Turbine SCADA dataset (mirrored public Kaggle dataset)
DATA_URL="https://raw.githubusercontent.com/yupeng0206/Wind-Turbine-SCADA-Data/master/Data/Turbine_Data.csv"
TMP_CSV="/tmp/Turbine_Data.csv"
wget -qO "$TMP_CSV" "$DATA_URL" || curl -sLo "$TMP_CSV" "$DATA_URL"

# Process the real data into the target Excel file
python3 << 'PYEOF'
import csv
import os
import openpyxl
from openpyxl.styles import Font, PatternFill

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "SCADA"

# Add headers
headers = ["Timestamp", "Wind_Speed_ms", "Active_Power_kW", "Theoretical_Power_kW"]
ws.append(headers)

# Format headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color="D9E1F2", end_color="D9E1F2", fill_type="solid")
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill

csv_file = "/tmp/Turbine_Data.csv"
row_count = 0

if os.path.exists(csv_file):
    try:
        with open(csv_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                ts = row.get('Unnamed: 0', row.get('Timestamp', ''))
                ws_val = row.get('WindSpeed', '')
                ap_val = row.get('ActivePower', '')
                
                if ts and ws_val and ap_val and ws_val != 'NaN' and ap_val != 'NaN':
                    try:
                        ws_ms = float(ws_val)
                        active = float(ap_val)
                        
                        # Data cleaning: SCADA often reports small negative power when idle
                        if active < -10: active = 0.0
                        
                        # Generate theoretical power from a standard 2MW curve
                        if ws_ms < 3.0: 
                            theo = 0.0
                        elif ws_ms >= 12.0: 
                            theo = 2000.0
                        else: 
                            theo = ((ws_ms - 3) / 9) ** 3 * 2000.0
                            
                        ws.append([ts, round(ws_ms, 2), round(active, 2), round(theo, 2)])
                        row_count += 1
                        
                        # We want roughly 1 month of 10-minute data = 4320 rows
                        if row_count >= 4320:
                            break
                    except ValueError:
                        continue
    except Exception as e:
        print(f"Error processing CSV: {e}")

# Fallback block (only triggers if the remote URL was totally inaccessible)
if row_count < 100:
    print("Warning: Failed to fetch online SCADA data. Generating fallback realistic subset.")
    import random
    from datetime import datetime, timedelta
    start_time = datetime(2022, 4, 1, 0, 0)
    for i in range(4320):
        ts = (start_time + timedelta(minutes=10 * i)).strftime("%Y-%m-%d %H:%M:%S")
        ws_ms = 7 + 4 * __import__('math').sin(i / 144 * 3.1415) + random.uniform(-1.5, 2.5)
        ws_ms = max(0.0, ws_ms)
        theo = 0.0 if ws_ms < 3.0 else (2000.0 if ws_ms >= 12.0 else ((ws_ms - 3) / 9) ** 3 * 2000.0)
        active = theo * random.uniform(0.95, 1.0)
        
        if 1000 <= i <= 1030 or 3000 <= i <= 3020: # FAULT
            active = 0.0
            ws_ms = max(5.0, ws_ms)
        elif 2000 <= i <= 2050: # UNDERPERFORMING
            active = theo * 0.4
            ws_ms = max(5.0, ws_ms)
            
        ws.append([ts, round(ws_ms, 2), round(active, 2), round(theo, 2)])

for col in ['A', 'B', 'C', 'D', 'E', 'F']:
    ws.column_dimensions[col].width = 22

ws.freeze_panes = 'A2'
wb.save("/home/ga/Documents/wind_scada_2022.xlsx")
print(f"Saved SCADA file with {ws.max_row - 1} records.")

PYEOF

chown ga:ga "$SCADA_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet
echo "Starting WPS Spreadsheet..."
su - ga -c "DISPLAY=:1 et '$SCADA_FILE' &"
sleep 6

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'wind_scada_2022' | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
else
    DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true
fi

sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="