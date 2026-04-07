#!/bin/bash
echo "=== Setting up build_water_quality_exceedance task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Remove any old artifacts
rm -f /home/ga/Documents/water_quality_report.xlsx 2>/dev/null || true
rm -f /tmp/ground_truth_exceedances.json 2>/dev/null || true

# Generate the realistic Water Quality Dataset and compute Ground Truth
# This prevents synthetic data complaints while ensuring robust ground truth that matches the exact dataset used.
python3 << 'PYEOF'
import os
import csv
import math
import random
import json
from datetime import datetime, timedelta

csv_source = '/workspace/data/water_quality.csv'
dest_path = '/home/ga/Documents/water_quality_raw.csv'

# Try to use mounted real data if it exists, otherwise generate a highly realistic
# dataset mirroring typical USGS Potomac River seasonal distributions
if os.path.exists(csv_source):
    import shutil
    shutil.copy(csv_source, dest_path)
else:
    stations = ['USGS-01646500', 'USGS-01638500', 'USGS-01631000']
    # Format: parameter, base_val, seasonal_amplitude, noise, limit
    params = [
        ('pH', 7.5, 0.5, 0.3),
        ('Nitrate', 5.0, 3.0, 2.0),
        ('Lead', 0.008, 0.002, 0.005),
        ('Arsenic', 0.005, 0.001, 0.004),
        ('Turbidity', 3.0, 1.5, 2.0),
        ('TDS', 350, 50, 80),
        ('Fluoride', 1.0, 0.2, 0.5),
        ('Copper', 0.5, 0.1, 0.4)
    ]

    rows = []
    start_date = datetime(2024, 1, 1)
    
    # Generate ~200 days of data
    for i in range(200):
        date = start_date + timedelta(days=i)
        date_str = date.strftime('%Y-%m-%d')
        doy = date.timetuple().tm_yday
        season = math.sin(doy * 2 * math.pi / 365.0)

        for s in stations:
            station_bias = stations.index(s) * 0.15
            for p, base, amp, noise in params:
                val = base + (amp * season) + (random.gauss(0, noise)) + station_bias
                val = max(0.001, round(val, 3))
                unit = 'SU' if p == 'pH' else ('NTU' if p == 'Turbidity' else 'mg/L')
                rows.append({
                    'Station_ID': s,
                    'Sample_Date': date_str,
                    'Parameter': p,
                    'Result_Value': val,
                    'Unit': unit
                })

    with open(dest_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['Station_ID', 'Sample_Date', 'Parameter', 'Result_Value', 'Unit'])
        writer.writeheader()
        writer.writerows(rows)

# Calculate EXACT ground truth from the populated CSV
ground_truth = {'parameters': {}, 'stations': {}}
limits = {
    'pH_Low': 6.5, 'pH_High': 8.5, 'Nitrate': 10.0, 'Lead': 0.015,
    'Arsenic': 0.010, 'Turbidity': 4.0, 'TDS': 500.0, 'Fluoride': 4.0, 'Copper': 1.3
}

with open(dest_path, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        p = row['Parameter']
        s = row['Station_ID']
        try:
            val = float(row['Result_Value'])
        except:
            continue

        if p not in ground_truth['parameters']:
            ground_truth['parameters'][p] = {'total': 0, 'exceedances': 0}
        if s not in ground_truth['stations']:
            ground_truth['stations'][s] = {'total': 0, 'exceedances': 0}

        ground_truth['parameters'][p]['total'] += 1
        ground_truth['stations'][s]['total'] += 1

        is_exceed = False
        if p == 'pH':
            if val < limits['pH_Low'] or val > limits['pH_High']:
                is_exceed = True
        elif p in limits:
            if val > limits[p]:
                is_exceed = True

        if is_exceed:
            ground_truth['parameters'][p]['exceedances'] += 1
            ground_truth['stations'][s]['exceedances'] += 1

with open('/tmp/ground_truth_exceedances.json', 'w') as f:
    json.dump(ground_truth, f)

PYEOF

chown ga:ga /home/ga/Documents/water_quality_raw.csv 2>/dev/null || true
chmod 644 /tmp/ground_truth_exceedances.json 2>/dev/null || true

# Start WPS Spreadsheet
echo "Starting WPS Spreadsheet..."
if ! pgrep -x "et" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 et &"
    sleep 5
fi

# Wait for WPS Window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Spreadsheet\|et"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true

# Close any initial popups like 'New features' or 'Templates'
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="