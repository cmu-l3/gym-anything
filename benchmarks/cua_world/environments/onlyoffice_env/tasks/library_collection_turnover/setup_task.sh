#!/bin/bash
set -euo pipefail

echo "=== Setting up Library Collection Turnover Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
echo $(date +%s) > /tmp/task_start_ts

# Clean up any residual files from previous runs
cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/spl_catalog_sample.csv"
GT_PATH="/tmp/ground_truth.json"

# Create Python script to generate the exact deterministic 10,000 row dataset
cat > /tmp/gen_data.py << 'PYEOF'
import random
import csv
import json
import sys

output_csv = sys.argv[1]
gt_json = sys.argv[2]

# Deterministic seed ensures consistent ground truth for verification
random.seed(42)

types = ["Book", "DVD", "Audiobook", "Graphic Novel"]
weights = [0.6, 0.2, 0.1, 0.1]
years = list(range(1990, 2024))
subjects = ["Fiction", "Non-Fiction", "Sci-Fi", "Mystery", "Biography", "History"]

data = []
headers = ["ItemID", "Title", "Author", "PublicationYear", "ItemType", "Subject", "CheckoutCount_YTD", "DaysInCatalog"]
data.append(headers)

total_items = 10000
total_checkouts = 0
total_weed = 0
circ_rates = []
type_counts = {"Book": 0, "DVD": 0, "Audiobook": 0, "Graphic Novel": 0}

for i in range(1, total_items + 1):
    item_id = f"SPL{i:06d}"
    title = f"Title {i}"
    author = f"Author {i}"
    pub_year = random.choice(years)
    item_type = random.choices(types, weights=weights)[0]
    subject = random.choice(subjects)
    
    checkouts = random.randint(0, 15)
    days = random.randint(30, 3650)

    # Weeding criteria: Book AND published before 2014 AND checkouts < 2
    is_weed = 1 if (item_type == "Book" and pub_year < 2014 and checkouts < 2) else 0
    circ_rate = checkouts / (days / 365.0)

    total_checkouts += checkouts
    total_weed += is_weed
    circ_rates.append(circ_rate)
    type_counts[item_type] += 1

    data.append([item_id, title, author, pub_year, item_type, subject, checkouts, days])

with open(output_csv, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)

gt = {
    "total_items": total_items,
    "total_checkouts": total_checkouts,
    "total_weed": total_weed,
    "avg_circ_rate": sum(circ_rates) / len(circ_rates),
    "type_counts": type_counts
}

with open(gt_json, 'w') as f:
    json.dump(gt, f)

print(f"Dataset generated at {output_csv} with {total_items} records.")
PYEOF

# Execute the generation script
sudo -u ga python3 /tmp/gen_data.py "$CSV_PATH" "$GT_PATH"

# Start ONLYOFFICE with an empty spreadsheet
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice.log 2>&1 &"

# Wait for application to be ready
wait_for_window "ONLYOFFICE\|Desktop Editors\|Spreadsheet" 30
sleep 5

# Ensure window is visible and maximized
focus_onlyoffice_window || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial state screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="