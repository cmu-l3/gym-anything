#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Urban Gentrification Analysis Task ==="

echo $(date +%s) > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/austin_census_tracts.csv"

# Generate realistic but synthetic US Census Data
cat > /tmp/create_census_data.py << 'PYEOF'
import csv
import random
import sys

random.seed(42)

headers = [
    "Tract_ID", "Total_Pop_2012", "Total_Pop_2022", 
    "Med_Inc_2012", "Med_Inc_2022", "Med_Rent_2012", "Med_Rent_2022", 
    "Edu_2012", "Edu_2022"
]
rows = []

# High gentrification tracts (East Austin)
east_austin_tracts = [
    ("48453000801", 3200, 4100, 35000, 85000, 800, 2100, 0.20, 0.55),
    ("48453000802", 2800, 3900, 40000, 92000, 850, 2200, 0.25, 0.60),
    ("48453000803", 4100, 4800, 32000, 78000, 750, 2000, 0.18, 0.50),
    ("48453000804", 3500, 4200, 38000, 95000, 900, 2400, 0.22, 0.62),
    ("48453000901", 2100, 3000, 45000, 105000, 950, 2500, 0.30, 0.65),
    ("48453000902", 3300, 4000, 42000, 98000, 880, 2300, 0.28, 0.63),
    ("48453001000", 4500, 5200, 36000, 82000, 820, 2150, 0.21, 0.52),
    ("48453001100", 2900, 3600, 41000, 89000, 860, 2250, 0.26, 0.58),
    ("48453001200", 3800, 4500, 39000, 86000, 840, 2180, 0.24, 0.56),
    ("48453001300", 4200, 5000, 37000, 84000, 810, 2120, 0.23, 0.54)
]

# Noise tracts with < 500 population but massive growth percentages (airport/industrial)
noise_tracts = [
    ("48453009800", 150, 300, 25000, 150000, 600, 3000, 0.10, 0.80),
    ("48453009900", 400, 450, 30000, 120000, 700, 2800, 0.15, 0.75)
]

# Normal/stable tracts across Travis County
stable_tracts = []
for i in range(140):
    stable_tracts.append((
        f"48453{10000 + i}",
        random.randint(2000, 6000),
        random.randint(2000, 6500),
        random.randint(50000, 120000),
        random.randint(55000, 130000),
        random.randint(1000, 2000),
        random.randint(1100, 2200),
        round(random.uniform(0.3, 0.7), 2),
        round(random.uniform(0.35, 0.75), 2)
    ))

rows.extend(east_austin_tracts)
rows.extend(noise_tracts)
rows.extend(stable_tracts)
random.shuffle(rows)

with open(sys.argv[1], 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(headers)
    writer.writerows(rows)
PYEOF

python3 /tmp/create_census_data.py "$CSV_PATH"
chown ga:ga "$CSV_PATH"

echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice_launch.log 2>&1 &"

wait_for_window "ONLYOFFICE\|Desktop Editors" 30
sleep 5
focus_onlyoffice_window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Give time for the UI to settle
sleep 2

DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="