#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Solar Farm Performance Analysis Task ==="

# Record task start timestamp
echo $(date +%s) > /tmp/solar_farm_performance_analysis_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

DATA_PATH="$WORKSPACE_DIR/clearview_solar_data.csv"
SPECS_PATH="$WORKSPACE_DIR/array_specifications.csv"

# Create Python script to generate the physical dataset
cat > /tmp/create_solar_data.py << 'PYEOF'
import csv
import math
import random
import datetime

# Fixed seed for deterministic data generation
random.seed(2024)

arrays = ["INV-001", "INV-002", "INV-003", "INV-004", "INV-005", "INV-006"]
capacities = {arr: 840 for arr in arrays}

# Write array specifications
with open('/home/ga/Documents/Spreadsheets/array_specifications.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["array_id", "dc_nameplate_kwp", "inverter_model", "tilt_deg", "azimuth_deg", "commissioning_date", "guaranteed_pr"])
    for arr in arrays:
        writer.writerow([arr, capacities[arr], "SMA-SunnyCentral-800", 20, 180, "2020-05-15", "75%"])

# Generate hourly generation records for 90 days
start_date = datetime.datetime(2024, 3, 1, 0, 0, 0)
days = 90
hours_per_day = 24

with open('/home/ga/Documents/Spreadsheets/clearview_solar_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "array_id", "power_output_kw", "poa_irradiance_wm2", "module_temp_c", "ambient_temp_c"])
    
    for day in range(days):
        # Seasonal ramp up in irradiance from March to May
        seasonal_factor = 0.8 + (0.4 * (day / days))
        
        # Stochastic cloud cover events
        cloudy_day = random.random() < 0.2
        cloud_factor = random.uniform(0.3, 0.7) if cloudy_day else 1.0
        
        for hour in range(hours_per_day):
            ts = start_date + datetime.timedelta(days=day, hours=hour)
            
            # Basic solar irradiance model (bell curve peaking at solar noon)
            if 6 <= hour <= 18:
                hour_angle = (hour - 12) * 15 # degrees
                irradiance = 1000 * math.cos(math.radians(hour_angle)) * seasonal_factor * cloud_factor
                irradiance = max(0, irradiance)
                
                # Introduce intra-day cloud noise
                if cloudy_day and 10 <= hour <= 14:
                    irradiance *= random.uniform(0.5, 0.9)
            else:
                irradiance = 0
                
            # Ambient temperature diurnal cycle
            if 6 <= hour <= 18:
                ambient_temp = 10 + 15 * math.sin(math.pi * (hour - 6) / 12) 
            else:
                ambient_temp = 10 - 5 * math.sin(math.pi * (hour - 18) / 12)
            ambient_temp += random.uniform(-2, 2)
            
            # Module temperature estimated via simple NOCT model
            module_temp = ambient_temp + (irradiance * 0.03)
            
            for arr in arrays:
                # Physics-based output generation
                temp_derate = 1 - 0.004 * max(0, module_temp - 25)
                output = capacities[arr] * (irradiance / 1000.0) * temp_derate * 0.95 # 0.95 inverter efficiency
                
                # Inject anomaly: Degradation on INV-004
                if arr == "INV-004":
                    output *= 0.85
                    
                # Inject anomaly: Outage on INV-002 (days 35-39)
                if arr == "INV-002" and 35 <= day <= 39:
                    output = 0
                    
                # Standard measurement noise
                output *= random.uniform(0.98, 1.02)
                if irradiance < 10:
                    output = 0
                
                writer.writerow([
                    ts.strftime("%Y-%m-%dT%H:%M:%S"),
                    arr,
                    round(output, 2),
                    round(irradiance, 1),
                    round(module_temp, 1),
                    round(ambient_temp, 1)
                ])
PYEOF

sudo -u ga python3 /tmp/create_solar_data.py

echo "Launching ONLYOFFICE with data file..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors "$DATA_PATH" > /tmp/onlyoffice_launch.log 2>&1 &

wait_for_window "ONLYOFFICE\|Desktop Editors\|clearview_solar_data" 30
sleep 5

WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot proving starting state
DISPLAY=:1 scrot /tmp/solar_farm_performance_analysis_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="