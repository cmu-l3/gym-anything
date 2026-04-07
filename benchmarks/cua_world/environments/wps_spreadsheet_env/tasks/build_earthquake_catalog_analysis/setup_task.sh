#!/bin/bash
echo "=== Setting up build_earthquake_catalog_analysis task ==="

export DISPLAY=${DISPLAY:-:1}
DATA_FILE="/home/ga/Documents/earthquake_catalog.xlsx"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create python script to fetch real USGS data and populate initial workbook
cat << 'EOF' > /tmp/prep_data.py
import urllib.request
import csv
import io
import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws = wb.active
ws.title = "EarthquakeData"

headers = ["time", "latitude", "longitude", "depth", "mag", "place"]
ws.append(headers)

# Format headers
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color="4F81BD", fill_type="solid")
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal="center")

# Try to fetch real data from USGS API
try:
    url = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=csv&starttime=2024-01-01&endtime=2024-01-31&minmagnitude=2.5&limit=150&orderby=time"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=15) as response:
        csv_data = response.read().decode('utf-8')
    
    reader = csv.DictReader(io.StringIO(csv_data))
    for row in reader:
        try:
            depth = float(row['depth'])
            mag = float(row['mag'])
            lat = float(row['latitude'])
            lon = float(row['longitude'])
            ws.append([row['time'], lat, lon, depth, mag, row['place']])
        except (ValueError, KeyError):
            pass
except Exception as e:
    print(f"Failed to fetch USGS data: {e}, using realistic fallback.")
    # Fallback realistic data to avoid total failure
    fallback = [
        ["2024-01-01T00:15:00Z", 35.0, -118.0, 10.5, 3.2, "California"],
        ["2024-01-01T01:40:00Z", 36.0, -119.0, 75.0, 4.5, "California"],
        ["2024-01-01T02:22:00Z", 37.0, -120.0, 310.0, 6.1, "California"],
        ["2024-01-01T03:10:00Z", 38.0, -121.0, 5.0, 2.8, "California"],
        ["2024-01-01T04:05:00Z", 39.0, -122.0, 50.0, 5.5, "California"],
        ["2024-01-01T05:30:00Z", 40.0, -123.0, 80.0, 3.8, "California"]
    ]
    for row in fallback:
        ws.append(row)

# Adjust widths
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 10
ws.column_dimensions['F'].width = 45

wb.save("/home/ga/Documents/earthquake_catalog.xlsx")
EOF

# Execute data prep
python3 /tmp/prep_data.py
chown ga:ga "$DATA_FILE"

# Record original modification time
stat -c %Y "$DATA_FILE" > /tmp/original_mtime.txt

# Start WPS Spreadsheet
su - ga -c "DISPLAY=:1 et '$DATA_FILE' >/dev/null 2>&1 &"

# Wait for WPS window to load
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "WPS Spreadsheets\|earthquake_catalog"; then
        break
    fi
    sleep 1
done
sleep 2

# Maximize and Focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "earthquake_catalog" 2>/dev/null || true
sleep 1

# Take Initial State Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="