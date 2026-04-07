#!/bin/bash
echo "=== Setting up building_tou_energy_analysis task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Target file path
FILE_PATH="/home/ga/Documents/hourly_load_data.xlsx"

# Remove any existing file
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate realistic 8760 commercial building load profile data
# We use a Python script to synthesize a high-fidelity dataset based on standard 
# commercial office profiles (to guarantee availability without relying on curl/internet in sandbox).
echo "Generating hourly load data..."
python3 << 'PYEOF'
import pandas as pd
import numpy as np
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Generate 8760 hours for a standard non-leap year
dates = pd.date_range(start='2023-01-01 00:00:00', periods=8760, freq='H')

# Create a realistic commercial office load profile
# Base load (night/weekend) + HVAC (weather dependent) + Occupancy (8am-6pm)
usage = []
np.random.seed(42)

for dt in dates:
    month = dt.month
    hour = dt.hour
    is_weekend = dt.dayofweek >= 5
    
    # Base load
    load = 50.0 + np.random.normal(0, 2.0)
    
    if not is_weekend:
        if 8 <= hour <= 18:
            # Occupancy load
            load += 120.0 + np.random.normal(0, 10.0)
            
            # HVAC cooling in summer (peaking in afternoon)
            if month in [6, 7, 8, 9] and 12 <= hour <= 17:
                load += 80.0 * np.sin((hour - 12) / 5.0 * np.pi) + np.random.normal(0, 5.0)
                
            # HVAC heating in winter (peaking in morning)
            if month in [12, 1, 2] and 8 <= hour <= 11:
                load += 60.0 * np.cos((hour - 8) / 3.0 * np.pi / 2) + np.random.normal(0, 4.0)
                
    usage.append(max(0, round(load, 2)))

# Write to Excel
wb = Workbook()
ws = wb.active
ws.title = "MeterData"

# Add headers
ws.append(["Timestamp", "Usage_kWh"])

# Format headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9D9D9', end_color='D9D9D9', fill_type='solid')
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Add data
for dt, val in zip(dates, usage):
    # Format timestamp as string to avoid excel date parsing ambiguities
    ws.append([dt.strftime('%Y-%m-%d %H:%M:%S'), val])

# Set column widths
ws.column_dimensions['A'].width = 22
ws.column_dimensions['B'].width = 15

# Save
wb.save('/home/ga/Documents/hourly_load_data.xlsx')
print(f"Created {len(dates)} rows of smart meter data.")
PYEOF

# Ensure proper ownership
chown ga:ga "$FILE_PATH" 2>/dev/null || true

# Record initial file stat
stat -c %Y "$FILE_PATH" > /tmp/initial_file_mtime.txt 2>/dev/null || echo "0" > /tmp/initial_file_mtime.txt

# Start WPS Spreadsheet with the file
echo "Starting WPS Spreadsheet..."
if ! pgrep -f "et" > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' &"
    sleep 8
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "hourly_load_data"; then
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "hourly_load_data" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="