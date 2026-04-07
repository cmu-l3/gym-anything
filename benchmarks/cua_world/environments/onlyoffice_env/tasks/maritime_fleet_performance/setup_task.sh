#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Maritime Fleet Performance Task ==="

# Record task start timestamp for anti-gaming checks
echo $(date +%s) > /tmp/maritime_fleet_performance_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Python script to generate real-world complexity maritime fleet data
cat > /tmp/create_fleet_data.py << 'PYEOF'
import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta

vessels = [
    {"Vessel_Name": "Pacific Voyager", "IMO_Number": "IMO9123456", "Vessel_Class": "Container", "Year_Built": 2010, "Design_Speed": 22, "Baseline_EEOI": 12.5},
    {"Vessel_Name": "Pacific Explorer", "IMO_Number": "IMO9123457", "Vessel_Class": "Container", "Year_Built": 2012, "Design_Speed": 22, "Baseline_EEOI": 12.0},
    {"Vessel_Name": "Pacific Navigator", "IMO_Number": "IMO9123458", "Vessel_Class": "Container", "Year_Built": 2015, "Design_Speed": 22, "Baseline_EEOI": 11.5},
    {"Vessel_Name": "Pacific Pioneer", "IMO_Number": "IMO9123459", "Vessel_Class": "Container", "Year_Built": 2004, "Design_Speed": 22, "Baseline_EEOI": 14.5}, 
    {"Vessel_Name": "Pacific Trader", "IMO_Number": "IMO9234567", "Vessel_Class": "Bulk Carrier", "Year_Built": 2008, "Design_Speed": 14, "Baseline_EEOI": 8.5},
    {"Vessel_Name": "Pacific Miner", "IMO_Number": "IMO9234568", "Vessel_Class": "Bulk Carrier", "Year_Built": 2011, "Design_Speed": 14, "Baseline_EEOI": 8.2},
    {"Vessel_Name": "Pacific Hauler", "IMO_Number": "IMO9234569", "Vessel_Class": "Bulk Carrier", "Year_Built": 2016, "Design_Speed": 14, "Baseline_EEOI": 7.8},
    {"Vessel_Name": "Pacific Transporter", "IMO_Number": "IMO9234570", "Vessel_Class": "Bulk Carrier", "Year_Built": 2005, "Design_Speed": 14, "Baseline_EEOI": 9.5}, 
    {"Vessel_Name": "Pacific Mariner", "IMO_Number": "IMO9345678", "Vessel_Class": "Tanker", "Year_Built": 2009, "Design_Speed": 15, "Baseline_EEOI": 10.5},
    {"Vessel_Name": "Pacific Supplier", "IMO_Number": "IMO9345679", "Vessel_Class": "Tanker", "Year_Built": 2013, "Design_Speed": 15, "Baseline_EEOI": 10.0},
    {"Vessel_Name": "Pacific Provider", "IMO_Number": "IMO9345680", "Vessel_Class": "Tanker", "Year_Built": 2018, "Design_Speed": 15, "Baseline_EEOI": 9.2},
    {"Vessel_Name": "Pacific Carrier", "IMO_Number": "IMO9345681", "Vessel_Class": "Tanker", "Year_Built": 2006, "Design_Speed": 15, "Baseline_EEOI": 11.2}, 
]

df_vessels = pd.DataFrame(vessels)

np.random.seed(2024)
random.seed(2024)

voyages = []
ports = ["Shanghai", "Singapore", "Rotterdam", "Los Angeles", "Busan", "Hong Kong", "Antwerp", "Hamburg", "Dubai", "Klang"]

for i in range(150):
    vessel = random.choice(vessels)
    dep_port = random.choice(ports)
    arr_port = random.choice([p for p in ports if p != dep_port])
    
    distance = random.uniform(3000, 10000)
    speed = vessel["Design_Speed"] * random.uniform(0.8, 0.95)
    days = distance / (speed * 24)
    
    dep_date = datetime(2024, 1, 1) + timedelta(days=random.uniform(0, 150))
    arr_date = dep_date + timedelta(days=days)
    
    cargo_capacity = 50000 if vessel["Vessel_Class"] == "Container" else (80000 if vessel["Vessel_Class"] == "Bulk Carrier" else 100000)
    cargo = cargo_capacity * random.uniform(0.7, 0.95)
    
    beaufort = random.randint(1, 8)
    if beaufort <= 3:
        weather = "Calm"
        weather_factor = 1.0
    elif beaufort <= 5:
        weather = "Moderate"
        weather_factor = 1.05
    elif beaufort <= 7:
        weather = "Rough"
        weather_factor = 1.15
    else:
        weather = "Severe"
        weather_factor = 1.25
        
    target_eeoi = vessel["Baseline_EEOI"] * weather_factor * random.uniform(0.95, 1.05)
    fuel = (target_eeoi * cargo * distance) / (3.114 * 10**6)
    
    voyages.append({
        "Voyage_ID": f"VOY-{1000+i}",
        "Vessel_Name": vessel["Vessel_Name"],
        "Departure_Port": dep_port,
        "Arrival_Port": arr_port,
        "Departure_Date": dep_date.strftime("%Y-%m-%d"),
        "Arrival_Date": arr_date.strftime("%Y-%m-%d"),
        "Distance_nm": round(distance, 1),
        "Fuel_HFO_MT": round(fuel, 1),
        "Average_Speed_knots": round(speed, 1),
        "Cargo_MT": round(cargo, 0),
        "Beaufort_Scale": beaufort,
        "Weather_Class": weather
    })

df_voyages = pd.DataFrame(voyages)

with pd.ExcelWriter('/home/ga/Documents/Spreadsheets/maritime_fleet_data.xlsx') as writer:
    df_voyages.to_excel(writer, sheet_name='Voyage Records', index=False)
    df_vessels.to_excel(writer, sheet_name='Vessel Registry', index=False)
PYEOF

sudo -u ga python3 /tmp/create_fleet_data.py
rm /tmp/create_fleet_data.py

# Launch ONLYOFFICE with the target file 
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors /home/ga/Documents/Spreadsheets/maritime_fleet_data.xlsx > /dev/null 2>&1 &"
sleep 5

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "maritime_fleet_data"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "maritime_fleet_data" 2>/dev/null || true

# Take initial screenshot as proof of setup
DISPLAY=:1 scrot /tmp/maritime_fleet_performance_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="