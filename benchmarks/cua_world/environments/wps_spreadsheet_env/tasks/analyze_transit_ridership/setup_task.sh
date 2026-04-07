#!/bin/bash
set -euo pipefail

echo "=== Setting up analyze_transit_ridership task ==="

export DISPLAY=${DISPLAY:-:1}
DATA_FILE="/home/ga/Documents/cta_ridership_oct2023.xlsx"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove previous artifact if present
rm -f "$DATA_FILE" 2>/dev/null || true

# Generate realistic data using Python
echo "Generating CTA ridership dataset..."
python3 << 'PYEOF'
import csv
import json
import urllib.request
import urllib.error
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()
ws_raw = wb.active
ws_raw.title = 'Raw_Data'

headers = ['Station_ID', 'Station_Name', 'Date', 'Day_Type', 'Rides']
ws_raw.append(headers)

data = []
fetch_success = False

try:
    # Attempt to fetch real data directly from the Chicago Data Portal API for Oct 2023
    print("Attempting to download data from Chicago Data Portal API...")
    url = "https://data.cityofchicago.org/resource/t2rn-p8d7.json?$where=date%20between%20'2023-10-01T00:00:00'%20and%20'2023-10-31T23:59:59'&$limit=5000"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    
    with urllib.request.urlopen(req, timeout=15) as response:
        raw_data = json.loads(response.read().decode())
        if len(raw_data) > 100:
            for row in raw_data:
                data.append([
                    row.get('station_id', ''),
                    row.get('stationname', ''),
                    row.get('date', '')[:10],
                    row.get('daytype', ''),
                    int(row.get('rides', 0))
                ])
            fetch_success = True
            print(f"Successfully downloaded {len(data)} records.")
except Exception as e:
    print(f"API fetch failed ({e}). Falling back to embedded dataset generator.")

if not fetch_success:
    # Fallback to a mathematically realistic embedded sample if network is down
    print("Using realistic embedded fallback data.")
    fallback_stations = [
        ("40010", "Austin-Forest Park"), ("40020", "Harlem-Lake"), ("40030", "Pulaski-Lake"),
        ("40040", "Quincy/Wells"), ("40050", "Davis"), ("40060", "Belmont-O'Hare"),
        ("40070", "Jackson/State"), ("40080", "Sheridan"), ("40090", "Damen-Brown"),
        ("40100", "Morse"), ("40120", "35th/Archer"), ("40130", "51st"),
        ("40140", "Dempster-Skokie"), ("40150", "Pulaski-Cermak"), ("40160", "LaSalle/Van Buren")
    ]
    import random
    random.seed(42) # Deterministic fallback
    
    for day in range(1, 32):
        date_str = f"2023-10-{day:02d}"
        day_of_week = (day + 6) % 7 # Oct 1, 2023 was a Sunday (6)
        daytype = 'U' if day_of_week == 6 else ('A' if day_of_week == 5 else 'W')
        
        for st_id, st_name in fallback_stations:
            base_rides = random.randint(1500, 8500)
            if st_id in ["40040", "40070", "40160"]: # Downtown stations
                base_rides = random.randint(12000, 35000)
                
            if daytype == 'W':
                rides = base_rides
            elif daytype == 'A':
                rides = int(base_rides * 0.45) # Saturday drop-off
            else:
                rides = int(base_rides * 0.30) # Sunday drop-off
                
            data.append([st_id, st_name, date_str, daytype, rides])

# Sort data by Station_ID, then Date
data.sort(key=lambda x: (x[0], x[2]))

stations_set = set()
for row in data:
    ws_raw.append(row)
    stations_set.add(row[1])

# Styling
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9D9D9', end_color='D9D9D9', fill_type='solid')

for cell in ws_raw[1]:
    cell.font = header_font
    cell.fill = header_fill

ws_raw.column_dimensions['B'].width = 25
ws_raw.column_dimensions['C'].width = 15

# Create Summary Sheet
ws_sum = wb.create_sheet(title='Station_Summary')
ws_sum.append(['Station_Name'])
for cell in ws_sum[1]:
    cell.font = header_font
    cell.fill = header_fill

for st in sorted(list(stations_set)):
    ws_sum.append([st])

ws_sum.column_dimensions['A'].width = 25
ws_sum.column_dimensions['B'].width = 20
ws_sum.column_dimensions['C'].width = 20
ws_sum.column_dimensions['D'].width = 20
ws_sum.column_dimensions['E'].width = 15

wb.save('/home/ga/Documents/cta_ridership_oct2023.xlsx')
print(f"Data ready: {len(data)} rows across {len(stations_set)} stations.")
PYEOF

# Ensure proper permissions
chown ga:ga "$DATA_FILE" 2>/dev/null || true

# Start WPS Spreadsheet
echo "Starting WPS Spreadsheet..."
if ! pgrep -x "et" > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$DATA_FILE' > /tmp/wps_task.log 2>&1 &"
    sleep 8
fi

# Maximize and Focus WPS Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "cta_ridership" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Wait and capture initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="