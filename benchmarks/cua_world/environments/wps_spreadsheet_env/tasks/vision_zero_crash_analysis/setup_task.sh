#!/bin/bash
set -e
echo "=== Setting up vision_zero_crash_analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/nyc_collisions.xlsx"

# Generate a highly realistic municipal traffic dataset (synthetic but contextually accurate)
python3 << 'PYEOF'
import random
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()
ws = wb.active
ws.title = "Crashes"

headers = [
    "CRASH DATE", "CRASH TIME", "BOROUGH", "ZIP CODE", "LATITUDE", "LONGITUDE",
    "LOCATION", "ON STREET NAME", "CROSS STREET NAME", "OFF STREET NAME",
    "NUMBER OF PEDESTRIANS INJURED", "NUMBER OF PEDESTRIANS KILLED",
    "NUMBER OF CYCLIST INJURED", "NUMBER OF CYCLIST KILLED",
    "NUMBER OF MOTORIST INJURED"
]
ws.append(headers)

streets = ["BROADWAY", "FLATBUSH AVE", "ATLANTIC AVE", "QUEENS BLVD", "3 AVE", "GRAND CONCOURSE", "NORTHERN BLVD", "BOWERY", "CANAL ST"]
boros = ["MANHATTAN", "BROOKLYN", "BROOKLYN", "QUEENS", "MANHATTAN", "BRONX", "QUEENS", "MANHATTAN", "MANHATTAN"]

random.seed(42)
# Generate ~5200 rows to ensure realistic complexity without crashing setup times
for i in range(5200):
    hour = int(random.gauss(15, 6)) % 24
    minute = random.randint(0, 59)
    time_str = f"{hour:02d}:{minute:02d}"
    date_str = f"01/{random.randint(1,31):02d}/2024"
    
    idx = random.randint(0, len(streets)-1)
    boro = boros[idx]
    street = streets[idx]
    
    # Pedestrian injuries are more common in late afternoon/evening
    ped_prob = 0.08 if hour >= 16 else 0.03
    ped_inj = random.choices([0, 1, 2], weights=[1-ped_prob, ped_prob*0.9, ped_prob*0.1])[0]
    
    # Cyclist injuries
    cyc_prob = 0.05 if hour >= 12 else 0.02
    cyc_inj = random.choices([0, 1], weights=[1-cyc_prob, cyc_prob])[0]
    
    mot_inj = random.choices([0, 1, 2], weights=[0.8, 0.15, 0.05])[0]
    
    ws.append([
        date_str, time_str, boro, "", "", "", "", street, "", "",
        ped_inj, 0, cyc_inj, 0, mot_inj
    ])

# Format headers securely
for cell in ws[1]:
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color='DDDDDD', end_color='DDDDDD', fill_type='solid')

# Set column widths for visibility
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 15
ws.column_dimensions['H'].width = 20
ws.column_dimensions['K'].width = 30
ws.column_dimensions['M'].width = 25

wb.save("/home/ga/Documents/nyc_collisions.xlsx")
print("Created nyc_collisions.xlsx successfully with 5200 crash records.")
PYEOF

chown ga:ga "$FILE_PATH"

# Ensure application is running
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "nyc_collisions"; then
        break
    fi
    sleep 1
done

# Maximize and focus window
DISPLAY=:1 wmctrl -r "nyc_collisions" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "nyc_collisions" 2>/dev/null || true

# Dismiss any potential dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for reference
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="