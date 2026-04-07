#!/bin/bash
echo "=== Setting up analyze_bikeshare_rebalancing task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/bikeshare_q3_data.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate realistic data dynamically to prevent hardcoded memorization
python3 << 'PYEOF'
import random
import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

random.seed(12345)
wb = Workbook()

# 1. Trips Sheet
ws_trips = wb.active
ws_trips.title = "Trips"
headers_trips = ["Trip_ID", "Start_Time", "End_Time", "Start_Station", "End_Station", "Rider_Type"]
ws_trips.append(headers_trips)

stations = [f"Station {i:02d}" for i in range(1, 31)]
rider_types = ["Casual", "Member"]
base_time = datetime.datetime(2023, 8, 15, 6, 0, 0)

for i in range(1, 801):
    start_station = random.choice(stations)
    # Create natural imbalances for the agent to find
    if random.random() < 0.15:
        end_station = "Station 05"
    elif random.random() < 0.15:
        end_station = "Station 12"
    elif random.random() < 0.10:
        start_station = "Station 22"
    else:
        end_station = random.choice(stations)
        
    start_time = base_time + datetime.timedelta(minutes=random.randint(0, 840))
    r_type = random.choice(rider_types)
    duration_mins = random.randint(12, 55) if r_type == "Casual" else random.randint(4, 25)
    end_time = start_time + datetime.timedelta(minutes=duration_mins)
    
    ws_trips.append([
        f"TRP{i:04d}", 
        start_time, 
        end_time, 
        start_station, 
        end_station, 
        r_type
    ])

# Format datetimes
for row in ws_trips.iter_rows(min_row=2, max_row=801, min_col=2, max_col=3):
    for cell in row:
        cell.number_format = 'yyyy-mm-dd hh:mm:ss'

# 2. Station Summary Sheet
ws_stations = wb.create_sheet("Station_Summary")
ws_stations.append(["Station_Name", "Total_Starts", "Total_Ends", "Net_Flow", "Action"])
for st in stations:
    ws_stations.append([st])

# 3. Rider Summary Sheet
ws_riders = wb.create_sheet("Rider_Summary")
ws_riders.append(["Rider Type", "Total Trips", "Avg Duration (Mins)"])
ws_riders.append(["Casual"])
ws_riders.append(["Member"])

# Styling
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='4F81BD', end_color='4F81BD', fill_type='solid')

for ws in [ws_trips, ws_stations, ws_riders]:
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center')
        
ws_trips.column_dimensions['A'].width = 12
ws_trips.column_dimensions['B'].width = 20
ws_trips.column_dimensions['C'].width = 20
ws_trips.column_dimensions['D'].width = 15
ws_trips.column_dimensions['E'].width = 15
ws_trips.column_dimensions['F'].width = 12

ws_stations.column_dimensions['A'].width = 15
ws_stations.column_dimensions['B'].width = 12
ws_stations.column_dimensions['C'].width = 12
ws_stations.column_dimensions['D'].width = 12
ws_stations.column_dimensions['E'].width = 15

ws_riders.column_dimensions['A'].width = 15
ws_riders.column_dimensions['B'].width = 12
ws_riders.column_dimensions['C'].width = 20

wb.save("/home/ga/Documents/bikeshare_q3_data.xlsx")
print("Created bikeshare dataset successfully.")
PYEOF

chown ga:ga "$FILE_PATH"

# Ensure WPS Spreadsheet is running and maximized
if ! pgrep -x "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "Spreadsheet"; then
            break
        fi
        sleep 1
    done
fi

DISPLAY=:1 wmctrl -r "Spreadsheet" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Spreadsheet" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="