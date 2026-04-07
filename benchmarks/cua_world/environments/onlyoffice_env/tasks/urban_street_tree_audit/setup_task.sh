#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Urban Street Tree Audit Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/urban_street_tree_audit_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/brooklyn_cb6_trees.csv"

# Generate the data
cat > /tmp/create_tree_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
import sys

output_path = sys.argv[1]
random.seed(2015)

headers = ['tree_id', 'tree_dbh', 'status', 'health', 'spc_common', 'borocode', 'nta_name', 'latitude', 'longitude']

species_counts = {
    "London planetree": 990,  # 22.0%
    "Honeylocust": 630,       # 14.0%
    "Callery pear": 400,
    "Pin oak": 350,
    "Norway maple": 300,
    "Littleleaf linden": 250,
    "Ginkgo": 200,
    "Cherry": 180,
    "Zelkova": 150,
    "Green ash": 150,
    "Sycamore": 100,
    "Red maple": 100,
    "Silver maple": 100,
    "American elm": 100,
    "Sweetgum": 100,
    "Other": 400
}

species_list = []
for k, v in species_counts.items():
    species_list.extend([k] * v)
random.shuffle(species_list)

# 34 specific high-risk trees. Total DBH = 980. Replacement cost = 980 * 150 = 147,000
high_risk_dbhs = [28] * 20 + [30] * 14
high_risk_trees = []
for dbh in high_risk_dbhs:
    status = random.choice(["Alive", "Dead"])
    health = "Poor" if status == "Alive" else ""
    high_risk_trees.append({
        'tree_dbh': dbh,
        'status': status,
        'health': health
    })

# Decoys to ensure they apply the exact logic: tree_dbh >= 24 AND (health = 'Poor' OR status = 'Dead')
decoys = []
# Decoy 1: DBH >= 24, but health is Good or Fair (Not high risk)
for _ in range(200):
    decoys.append({'tree_dbh': random.randint(24, 40), 'status': 'Alive', 'health': random.choice(['Good', 'Fair'])})

# Decoy 2: Status is Dead, but DBH < 24 (Not high risk)
for _ in range(100):
    decoys.append({'tree_dbh': random.randint(5, 23), 'status': 'Dead', 'health': ''})

# Decoy 3: Health is Poor, but DBH < 24 (Not high risk)
for _ in range(100):
    decoys.append({'tree_dbh': random.randint(5, 23), 'status': 'Alive', 'health': 'Poor'})

# Regular trees to fill the rest (4500 - 34 - 400 = 4066)
regulars = []
for _ in range(4066):
    regulars.append({'tree_dbh': random.randint(3, 23), 'status': 'Alive', 'health': random.choice(['Good', 'Fair'])})

all_tree_specs = high_risk_trees + decoys + regulars
random.shuffle(all_tree_specs)

tree_id_counter = 100000

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(headers)
    for i, spec in enumerate(all_tree_specs):
        tree_id_counter += 1
        writer.writerow([
            tree_id_counter,
            spec['tree_dbh'],
            spec['status'],
            spec['health'],
            species_list[i],
            '3',
            'BK31',
            f"40.{random.randint(650000, 690000)}",
            f"-73.{random.randint(970000, 999999)}"
        ])
PYEOF

python3 /tmp/create_tree_data.py "$CSV_PATH"
chown ga:ga "$CSV_PATH"

# Launch ONLYOFFICE
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice.log 2>&1 &"

# Wait for application to launch and be visible
wait_for_window "ONLYOFFICE\|Desktop Editors" 30
sleep 5

# Maximize and focus window
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
su - ga -c "DISPLAY=:1 import -window root /tmp/urban_street_tree_audit_initial_screenshot.png" || true

echo "=== Task setup complete ==="