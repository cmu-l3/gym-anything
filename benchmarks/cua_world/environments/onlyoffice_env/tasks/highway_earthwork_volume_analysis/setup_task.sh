#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Highway Earthwork Volume Analysis Task ==="

# Record task start timestamp for anti-gaming verification
echo $(date +%s) > /tmp/highway_earthwork_volume_analysis_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

CSV_PATH="$WORKSPACE_DIR/sr99_cross_sections.csv"
FORMULAS_PATH="$DOCS_DIR/earthwork_formulas.txt"

# Generate dataset and calculate ground truth via Python script
cat > /tmp/generate_earthwork_data.py << 'PYEOF'
import csv
import random

random.seed(42)
stations = list(range(10000, 12501, 50))
# Insert a few irregular stations
stations.insert(10, 10475)
stations.insert(25, 11215)
stations.sort()

data = []
for s in stations:
    exist_elev = 150.0 + random.uniform(-5, 5)
    prop_elev = 148.0 + random.uniform(-2, 2)
    
    # Generate realistic cut/fill based on relative elevation
    if exist_elev > prop_elev:
        cut = random.uniform(50, 200)
        fill = random.uniform(0, 20)
    else:
        cut = random.uniform(0, 20)
        fill = random.uniform(50, 200)
    data.append([s, round(exist_elev, 2), round(prop_elev, 2), round(cut, 2), round(fill, 2)])

with open('/home/ga/Documents/Spreadsheets/sr99_cross_sections.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Station_ft", "Existing_Elevation_ft", "Proposed_Elevation_ft", "Cut_Area_sqft", "Fill_Area_sqft"])
    for r in data:
        writer.writerow(r)

# Calculate ground truth Mass Haul to be used by verifier
prev_s, prev_cut, prev_fill = data[0][0], data[0][3], data[0][4]
mass_haul = 0.0

for r in data[1:]:
    s, _, _, cut, fill = r
    dist = s - prev_s
    cut_vol = dist * (prev_cut + cut) / 54.0
    fill_vol = dist * (prev_fill + fill) / 54.0
    adj_fill = fill_vol * 1.15
    net = cut_vol - adj_fill
    mass_haul += net
    prev_s, prev_cut, prev_fill = s, cut, fill

with open('/tmp/earthwork_ground_truth.txt', 'w') as f:
    f.write(str(mass_haul))
PYEOF

python3 /tmp/generate_earthwork_data.py
chown ga:ga "$CSV_PATH"
chown ga:ga /tmp/earthwork_ground_truth.txt

# Create formula reference file
cat > "$FORMULAS_PATH" << 'EOF'
EARTHWORK CALCULATION FORMULAS
==============================
1. Distance (L): Current Station - Previous Station
2. Volume by Average End Area Method (Cubic Yards):
   Volume = L * (Previous Area + Current Area) / 54
   *Note: Dividing by 54 converts sq-ft * ft into cubic yards (2 * 27 = 54)*
3. Adjusted Fill Volume (Cubic Yards):
   Adjusted Fill = Fill Volume * 1.15
   *(Using 15% shrinkage/compaction factor)*
4. Net Volume (Cubic Yards):
   Net Volume = Cut Volume - Adjusted Fill Volume
5. Cumulative Mass Haul:
   Running total of Net Volume down the alignment
EOF
chown ga:ga "$FORMULAS_PATH"

# Start ONLYOFFICE and open the generated CSV
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice.log 2>&1 &"

# Wait for ONLYOFFICE window to appear
wait_for_window "ONLYOFFICE\|Desktop Editors" 30

# Maximize window
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="