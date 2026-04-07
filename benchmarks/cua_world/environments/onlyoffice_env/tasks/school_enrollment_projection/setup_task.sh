#!/bin/bash
set -euo pipefail

echo "=== Setting up School Enrollment Projection Task ==="

# Source ONLYOFFICE task utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/enrollment_projection_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Python script to generate the demographic data
cat > /tmp/create_enrollment_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import os

workspace = "/home/ga/Documents/Spreadsheets"

# 1. Regional Births (2013-2023)
# Show a slight decline over time, typical for many suburban US districts.
births_data = [
    {"Year": 2013, "Total_Births": 500},
    {"Year": 2014, "Total_Births": 510},
    {"Year": 2015, "Total_Births": 490},
    {"Year": 2016, "Total_Births": 480},
    {"Year": 2017, "Total_Births": 460},
    {"Year": 2018, "Total_Births": 450},
    {"Year": 2019, "Total_Births": 440},
    {"Year": 2020, "Total_Births": 420},
    {"Year": 2021, "Total_Births": 430},
    {"Year": 2022, "Total_Births": 435},
    {"Year": 2023, "Total_Births": 425},
]

with open(os.path.join(workspace, "regional_births.csv"), "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["Year", "Total_Births"])
    writer.writeheader()
    writer.writerows(births_data)

# 2. Historical Enrollment (2018-2023)
# To make verification deterministic and clear, we use exact transition ratios.
# Birth-to-K ratio = exactly 0.90
# K->1 = 0.98, 1->2 = 1.01, 2->3 = 1.00, 3->4 = 0.99, 4->5 = 1.02, 5->6 = 1.05 (Middle school influx)
# 6->7 = 0.99, 7->8 = 1.00, 8->9 = 1.08 (High school influx), 9->10 = 0.95, 10->11 = 0.92, 11->12 = 0.98

years = [2018, 2019, 2020, 2021, 2022, 2023]
enrollment_data = []

# Seed 2018 data (base year)
base_2018 = {
    "Year": 2018,
    "K": 450,  # 500 * 0.90
    "G1": 460, "G2": 455, "G3": 470, "G4": 465, "G5": 480,
    "G6": 510, "G7": 505, "G8": 490, 
    "G9": 540, "G10": 510, "G11": 495, "G12": 485
}
enrollment_data.append(base_2018)

# Ratios mapping
ratios = {
    "G1": 0.98, "G2": 1.01, "G3": 1.00, "G4": 0.99, "G5": 1.02,
    "G6": 1.05, "G7": 0.99, "G8": 1.00, "G9": 1.08, "G10": 0.95,
    "G11": 0.92, "G12": 0.98
}

grades = ["K", "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10", "G11", "G12"]

for y in range(2019, 2024):
    prev = enrollment_data[-1]
    curr = {"Year": y}
    
    # Calculate K based on births 5 years prior * 0.90
    birth_year = y - 5
    birth_val = next(b["Total_Births"] for b in births_data if b["Year"] == birth_year)
    curr["K"] = int(round(birth_val * 0.90))
    
    # Calculate other grades based on ratios
    curr["G1"] = int(round(prev["K"] * ratios["G1"]))
    curr["G2"] = int(round(prev["G1"] * ratios["G2"]))
    curr["G3"] = int(round(prev["G2"] * ratios["G3"]))
    curr["G4"] = int(round(prev["G3"] * ratios["G4"]))
    curr["G5"] = int(round(prev["G4"] * ratios["G5"]))
    curr["G6"] = int(round(prev["G5"] * ratios["G6"]))
    curr["G7"] = int(round(prev["G6"] * ratios["G7"]))
    curr["G8"] = int(round(prev["G7"] * ratios["G8"]))
    curr["G9"] = int(round(prev["G8"] * ratios["G9"]))
    curr["G10"] = int(round(prev["G9"] * ratios["G10"]))
    curr["G11"] = int(round(prev["G10"] * ratios["G11"]))
    curr["G12"] = int(round(prev["G11"] * ratios["G12"]))
    
    enrollment_data.append(curr)

with open(os.path.join(workspace, "historical_enrollment.csv"), "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["Year"] + grades)
    writer.writeheader()
    writer.writerows(enrollment_data)

PYEOF

chmod +x /tmp/create_enrollment_data.py
sudo -u ga /tmp/create_enrollment_data.py

# Launch ONLYOFFICE to start the session
echo "Launching ONLYOFFICE Spreadsheet Editor..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_launch.log 2>&1 &
sleep 5

# Ensure it is focused and maximized
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'ONLYOFFICE' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot for evidence
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task Setup Complete ==="