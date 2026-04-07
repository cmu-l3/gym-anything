#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Crop Yield and Soil Nutrient Analysis Task ==="

# Record task start timestamp for anti-gaming
TASK_START=$(date +%s)
echo $TASK_START > /tmp/crop_soil_nutrient_analysis_start_ts

# Clean up any previous task artifacts
cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

DATA_PATH="$WORKSPACE_DIR/county_soil_crop_data.csv"

# Remove any existing output from previous runs
rm -f "$WORKSPACE_DIR/soil_crop_analysis.xlsx" 2>/dev/null || true

# Python script to deterministically generate the agricultural dataset
cat > /tmp/generate_ag_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
import sys

output_path = sys.argv[1]
random.seed(2023)  # Deterministic generation

townships = ["Bean Blossom", "Indian Creek", "Perry", "Salt Creek", "Van Buren"]
soil_textures = ["Silt Loam", "Silty Clay Loam", "Loam", "Clay Loam"]
crops = ["Corn", "Soybeans", "Winter Wheat"]

# Expected distributions to ensure ~20 low pH, ~18 low P, ~15 low K out of 150
def get_ph():
    r = random.random()
    if r < 0.133: return round(random.uniform(4.8, 5.4), 1)  # ~20 low
    elif r < 0.85: return round(random.uniform(5.5, 7.0), 1) # Optimal
    else: return round(random.uniform(7.1, 7.5), 1)          # High

def get_p():
    r = random.random()
    if r < 0.12: return round(random.uniform(5.0, 14.5), 1)  # ~18 low
    elif r < 0.40: return round(random.uniform(15.0, 29.5), 1) # Medium
    else: return round(random.uniform(30.0, 65.0), 1)          # Optimal

def get_k():
    r = random.random()
    if r < 0.10: return int(random.uniform(60, 119))         # ~15 low
    elif r < 0.45: return int(random.uniform(120, 169))      # Medium
    else: return int(random.uniform(170, 280))               # Optimal

records = []
crop_counts = {"Corn": 60, "Soybeans": 50, "Winter Wheat": 40}

# Generate base crop assignments
crop_list = ["Corn"]*60 + ["Soybeans"]*50 + ["Winter Wheat"]*40
random.shuffle(crop_list)

for i in range(1, 151):
    plot_id = f"MC-{i:03d}"
    farm_name = f"{random.choice(['Miller', 'Smith', 'Hostetler', 'Wagler', 'Yoder', 'Graber', 'Schrock', 'Bontrager', 'Kemp', 'Stoll'])} {random.choice(['Farms', 'Acres', 'Fields', 'Valley'])}"
    township = random.choice(townships)
    crop = crop_list[i-1]
    
    ph = get_ph()
    p = get_p()
    k = get_k()
    
    om = round(random.uniform(1.5, 5.5), 1)
    n_ppm = int(random.uniform(10, 85))
    cec = int(random.uniform(8, 28))
    texture = random.choice(soil_textures)
    
    # Calculate realistic yield based on crop and limiting factors
    base_yield = {"Corn": 190, "Soybeans": 60, "Winter Wheat": 75}[crop]
    
    yield_multiplier = 1.0
    if ph < 5.5: yield_multiplier *= random.uniform(0.75, 0.85)  # 15-25% penalty
    if p < 15: yield_multiplier *= random.uniform(0.80, 0.90)    # 10-20% penalty
    if k < 120: yield_multiplier *= random.uniform(0.82, 0.90)   # 10-18% penalty
    
    # Add random noise +/- 8%
    noise = random.uniform(0.92, 1.08)
    
    final_yield = round(base_yield * yield_multiplier * noise, 1)
    
    planting_date = {"Corn": "04/25/2023", "Soybeans": "05/10/2023", "Winter Wheat": "09/30/2022"}[crop]
    harvest_date = {"Corn": "10/15/2023", "Soybeans": "10/05/2023", "Winter Wheat": "07/10/2023"}[crop]
    prev_crop = random.choice([c for c in crops if c != crop])
    
    records.append([
        plot_id, farm_name, township, crop, ph, om, n_ppm, p, k, cec, 
        texture, final_yield, planting_date, harvest_date, prev_crop
    ])

# Write to CSV
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow([
        "Plot_ID", "Farm_Name", "Township", "Crop", "Soil_pH", 
        "Organic_Matter_Pct", "Nitrogen_ppm", "Phosphorus_ppm", "Potassium_ppm", 
        "CEC_meq", "Soil_Texture", "Yield_bu_ac", "Planting_Date", 
        "Harvest_Date", "Previous_Crop"
    ])
    writer.writerows(records)

print(f"Generated {len(records)} agricultural records at {output_path}")
PYEOF

chmod +x /tmp/generate_ag_data.py
sudo -u ga /tmp/generate_ag_data.py "$DATA_PATH"

# Ensure ONLYOFFICE is fully stopped
kill_onlyoffice ga
sleep 2

# Launch ONLYOFFICE in spreadsheet mode with the generated CSV
echo "Launching ONLYOFFICE Spreadsheet Editor..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors "$DATA_PATH" > /tmp/onlyoffice_launch.log 2>&1 &
sleep 6

# Wait for ONLYOFFICE window to appear
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE\|Desktop Editors" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        echo "ONLYOFFICE window detected: $WID"
        break
    fi
    sleep 1
done

if [ -n "$WID" ]; then
    # Focus and Maximize
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any CSV import dialogs by sending Enter key
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
fi

# Take initial screenshot showing the raw data loaded
DISPLAY=:1 import -window root /tmp/crop_soil_nutrient_analysis_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="