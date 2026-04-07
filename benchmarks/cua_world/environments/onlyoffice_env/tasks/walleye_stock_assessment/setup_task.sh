#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Walleye Stock Assessment Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/walleye_stock_assessment_start_ts

# Clean up existing ONLYOFFICE instances to ensure a clean state
cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# ===================================================================
# Create Walleye Standards Reference File
# ===================================================================
cat > "$DOCS_DIR/walleye_standards.txt" << 'EOF'
MINNESOTA DEPARTMENT OF NATURAL RESOURCES
STANDARD FISHERIES INDICES REFERENCE - WALLEYE (Sander vitreus)

1. GABELHOUSE LENGTH CATEGORIES (mm)
------------------------------------
Sub-stock:   < 250 mm
Stock:       250 - 379 mm
Quality:     380 - 509 mm
Preferred:   510 - 629 mm
Memorable:   630 - 759 mm
Trophy:      >= 760 mm

2. PROPORTIONAL SIZE DISTRIBUTION (PSD) EQUATIONS
-------------------------------------------------
PSD = (Number of fish >= Quality length / Number of fish >= Stock length) * 100
PSD-P = (Number of fish >= Preferred length / Number of fish >= Stock length) * 100

3. STANDARD WEIGHT (Ws) EQUATION
--------------------------------
Based on Anderson & Neumann (1996) standard weight equation for Walleye:
log10(Ws) = -5.453 + 3.180 * log10(Total Length in mm)

Where Ws is the standard weight in grams.

4. RELATIVE WEIGHT (Wr) EQUATION
--------------------------------
Wr = (Actual Weight / Ws) * 100
Note: Wr should only be calculated for fish >= Stock length (250 mm).
EOF

# ===================================================================
# Python Script to Generate Biologically Realistic Survey Data
# ===================================================================
cat > /tmp/generate_fisheries_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
import math
import os

random.seed(2024)

workspace_dir = "/home/ga/Documents/Spreadsheets"
effort_file = os.path.join(workspace_dir, "net_effort_log.csv")
catch_file = os.path.join(workspace_dir, "gill_net_catches.csv")

# 1. Generate Net Effort Log (24 lifts across 8 stations)
stations = [f"VRM-0{i}" for i in range(1, 9)]
effort_data = []
net_id = 1

for station in stations:
    for lift in range(1, 4):  # 3 lifts per station
        set_date = f"2024-09-{10 + lift}"
        lift_date = f"2024-09-{11 + lift}"
        effort_hours = round(random.uniform(18.5, 22.0), 1)
        depth_m = round(random.uniform(3.0, 12.0), 1)
        temp_c = round(random.uniform(14.5, 17.0), 1)
        secchi_m = round(random.uniform(2.5, 4.0), 1)
        
        effort_data.append({
            "net_lift_id": f"NL-24-{net_id:03d}",
            "station_id": station,
            "set_date": set_date,
            "lift_date": lift_date,
            "effort_hours": effort_hours,
            "depth_m": depth_m,
            "surface_temp_c": temp_c,
            "secchi_m": secchi_m
        })
        net_id += 1

with open(effort_file, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=effort_data[0].keys())
    writer.writeheader()
    writer.writerows(effort_data)

# 2. Generate Gill Net Catches (~180 walleye)
catch_data = []
fish_id = 1001

for effort in effort_data:
    # Poisson-like catch distribution, lambda=7.5
    num_fish = int(round(random.gammavariate(7.5, 1)))
    
    for _ in range(num_fish):
        # Age distribution (right skewed, typical for walleye)
        age = int(round(random.gammavariate(3.5, 1.2)))
        age = max(1, min(15, age))  # Bound between 1 and 15
        
        # von Bertalanffy growth model with individual variation
        # L_inf = 680, K = 0.18, t0 = -0.5
        mean_length = 680 * (1 - math.exp(-0.18 * (age + 0.5)))
        length_variation = random.gauss(1.0, 0.08)
        total_length_mm = int(round(mean_length * length_variation))
        
        # Limit minimum length to realistic net retention size
        total_length_mm = max(150, total_length_mm)
        
        # Standard weight formula + natural body condition variation
        # log10(Ws) = -5.453 + 3.180 * log10(TL)
        log_ws = -5.453 + 3.180 * math.log10(total_length_mm)
        ws = 10 ** log_ws
        
        # Wr (Relative weight) varies around 95 (average condition)
        wr = random.gauss(95, 8)
        weight_g = int(round(ws * (wr / 100)))
        
        sex = random.choice(["M", "F", "U"])
        if total_length_mm > 550:
            sex = "F" # Large fish are predominantly female
            
        mesh_panel = random.choice([19, 25, 32, 38, 51])
        
        catch_data.append({
            "fish_id": f"WAE-{fish_id}",
            "station_id": effort["station_id"],
            "net_lift_id": effort["net_lift_id"],
            "species": "WAE",
            "total_length_mm": total_length_mm,
            "weight_g": weight_g,
            "age_years": age,
            "sex": sex,
            "mesh_panel_mm": mesh_panel,
            "capture_date": effort["lift_date"]
        })
        fish_id += 1

with open(catch_file, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=catch_data[0].keys())
    writer.writeheader()
    writer.writerows(catch_data)

PYEOF

# Run the python script to generate data
sudo -u ga python3 /tmp/generate_fisheries_data.py

# Fix permissions
chown -R ga:ga "$DOCS_DIR"

# Launch ONLYOFFICE empty spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_launch.log 2>&1 &
sleep 6

# Configure window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot showing environment setup
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="