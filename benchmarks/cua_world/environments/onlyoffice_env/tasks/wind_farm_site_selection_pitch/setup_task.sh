#!/bin/bash
set -euo pipefail

echo "=== Setting up Wind Farm Site Selection Pitch Task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/Documents/Presentations/site_alpha_pitch.pptx 2>/dev/null || true

# Prepare directories
mkdir -p /home/ga/Documents/Spreadsheets
mkdir -p /home/ga/Documents/Presentations
mkdir -p /var/lib/app/ground_truth

# Generate realistic 8760-hour wind dataset and ground truth
cat > /tmp/generate_wind_data.py << 'PYEOF'
import csv
import random
import json
import os
import math

random.seed(42) # Deterministic generation

output_csv = '/home/ga/Documents/Spreadsheets/nrel_hourly_wind_2023.csv'
truth_json = '/var/lib/app/ground_truth/wind_metrics.json'

total_speed = 0.0
max_speed = 0.0
operational_hours = 0
total_hours = 8760

with open(output_csv, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Date", "Hour", "Wind_Speed_80m_ms", "Wind_Direction_deg", "Temperature_C"])
    
    for day in range(1, 366):
        # Add seasonal variation (windier in spring/fall)
        seasonal_factor = 1.0 + 0.2 * math.sin(day / 365.0 * 2 * math.pi)
        
        for hour in range(24):
            # Add diurnal variation (windier in afternoon)
            diurnal_factor = 1.0 + 0.15 * math.sin((hour - 8) / 24.0 * 2 * math.pi)
            
            # Base weibull distribution for wind speed
            base_ws = random.weibullvariate(7.0, 2.0)
            ws = base_ws * seasonal_factor * diurnal_factor
            
            # Occasional extreme weather events
            if random.random() < 0.005:
                ws += random.uniform(10.0, 18.0)
                
            ws = round(max(0.0, ws), 2)
            
            total_speed += ws
            if ws > max_speed:
                max_speed = ws
            if 4.0 <= ws <= 25.0:
                operational_hours += 1
                
            writer.writerow([
                f"2023-01-{day:03d}", # Simplified date for spreadsheet
                f"{hour:02d}:00",
                ws,
                random.randint(0, 359),
                round(random.uniform(-5.0, 35.0), 1)
            ])

# Calculate exact ground truth values
avg_speed = total_speed / total_hours
op_fraction = (operational_hours / total_hours) * 100.0

truth = {
    "avg_wind_speed": round(avg_speed, 1),
    "max_wind_speed": round(max_speed, 1),
    "op_fraction": round(op_fraction, 1)
}

os.makedirs(os.path.dirname(truth_json), exist_ok=True)
with open(truth_json, 'w') as f:
    json.dump(truth, f)

# Make sure only root can read truth
os.chmod(truth_json, 0o600)

print(f"Generated 8760 rows. Avg: {truth['avg_wind_speed']}, Max: {truth['max_wind_speed']}, Op%: {truth['op_fraction']}")
PYEOF

python3 /tmp/generate_wind_data.py

# Create site specifications text file
cat > /home/ga/Documents/site_specifications.txt << 'EOF'
=====================================================
SITE SPECIFICATIONS: Tehachapi Site Alpha
=====================================================

Overview:
Proposed 120MW wind generation facility located in the Tehachapi Pass wind resource area. 

Location Details:
- Parcel ID: APN 314-159-22
- Coordinates: 35.1025° N, 118.3411° W
- Elevation: 1,220 meters ASL
- Interconnection: 4.2 miles to nearest SCE 230kV substation

Environmental Constraints & CEQA Requirements:
- A 500-foot setback buffer is required from the eastern parcel boundary due to active Mojave Desert Tortoise habitat.
- Construction activities must halt during high wind events exceeding 20 m/s to prevent fugitive dust emissions.
- Avian radar systems must be deployed to monitor California Condor flight paths.

Turbine Specifications:
- Proposed Model: Vestas V150-4.2 MW
- Hub Height: 80 meters
- Cut-in Speed: 4.0 m/s
- Cut-out Speed: 25.0 m/s
=====================================================
EOF

# Fix permissions
chown -R ga:ga /home/ga/Documents

# Start ONLYOFFICE Spreadsheet with the CSV
echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors /home/ga/Documents/Spreadsheets/nrel_hourly_wind_2023.csv &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Desktop Editors\|ONLYOFFICE"; then
        echo "ONLYOFFICE window detected"
        break
    fi
    sleep 1
done

sleep 3

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true

# Take initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="