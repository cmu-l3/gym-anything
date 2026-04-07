#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Wetland Bird Diversity Analysis Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/wetland_bird_analysis_start_ts

# Clean up environment
cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/wetland_bird_surveys.csv"

# Generate the deterministic synthetic dataset
cat > /tmp/create_bird_data.py << 'PYEOF'
#!/usr/bin/env python3
"""
Generate deterministic wetland bird survey data (seed=2024).
12 Sites, 5 Years (2019-2023).
"""
import csv
import sys
import random
from datetime import datetime, timedelta

output_path = sys.argv[1]
random.seed(2024)

# Site definitions
sites = []
for i in range(1, 13):
    site_id = f"WM-{i:02d}"
    if site_id == "WM-03":
        stype, qual = "Pristine Sedge Meadow", "Excellent"
    elif site_id == "WM-09":
        stype, qual = "Degraded Marsh", "Poor"
    else:
        types = ["Emergent Marsh", "Forested Wetland", "Riverine Backwater", "Wet Prairie"]
        stype, qual = random.choice(types), random.choice(["Good", "Moderate"])
    sites.append({"id": site_id, "type": stype, "quality": qual})

# Species definitions and base probabilities
species_list = {
    "Red-winged Blackbird": {"base": 20, "trend": 1.0},
    "Mallard": {"base": 12, "trend": 1.0},
    "Swamp Sparrow": {"base": 8, "trend": 1.0},
    "Marsh Wren": {"base": 6, "trend": 1.0},
    "Common Yellowthroat": {"base": 7, "trend": 1.0},
    "Great Blue Heron": {"base": 3, "trend": 1.0},
    "Wood Duck": {"base": 4, "trend": 1.0},
    "Sora": {"base": 3, "trend": 1.0},
    "Virginia Rail": {"base": 2, "trend": 1.0},
    "Pied-billed Grebe": {"base": 2, "trend": 1.0},
    "American Coot": {"base": 5, "trend": 1.0},
    "Yellow-headed Blackbird": {"base": 3, "trend": 1.0},
    "Song Sparrow": {"base": 5, "trend": 1.0},
    "Tree Swallow": {"base": 8, "trend": 1.0},
    "Barn Swallow": {"base": 6, "trend": 1.0},
    "Belted Kingfisher": {"base": 2, "trend": 1.0},
    # Declining species (Conservation concern)
    "Rusty Blackbird": {"base": 5, "trend": 0.70},  # ~30% drop per year
    "Black Tern": {"base": 4, "trend": 0.75},       # ~25% drop per year
    "American Bittern": {"base": 3, "trend": 0.80},   # ~20% drop per year
    # Increasing species
    "Canada Goose": {"base": 6, "trend": 1.25},     # 25% increase per year
    "Sandhill Crane": {"base": 3, "trend": 1.30},   # 30% increase per year
}

years = [2019, 2020, 2021, 2022, 2023]
observers = ["J. Audubon", "R. Peterson", "D. Sibley", "K. Kaufman"]

rows = []
survey_id_counter = 1000

for year in years:
    for site in sites:
        # 1 survey per site per year
        survey_id = f"SURV-{survey_id_counter}"
        survey_id_counter += 1
        
        # Determine survey date
        day_offset = random.randint(0, 30)
        date_str = (datetime(year, 5, 15) + timedelta(days=day_offset)).strftime("%Y-%m-%d")
        observer = random.choice(observers)
        
        # Determine species present and counts
        for sp, props in species_list.items():
            # Calculate expected count based on base, trend, and site quality
            year_idx = year - 2019
            expected = props["base"] * (props["trend"] ** year_idx)
            
            # Apply site-specific multipliers
            if site["id"] == "WM-09": # Degraded
                if sp == "Red-winged Blackbird":
                    expected *= 4.0 # High dominance
                elif sp in ["Canada Goose", "Mallard"]:
                    expected *= 1.5
                else:
                    expected *= 0.1 # Very low richness
            elif site["id"] == "WM-03": # Pristine
                expected *= 1.5 # High richness/abundance
                if sp in ["Rusty Blackbird", "Black Tern", "American Bittern", "Sora", "Virginia Rail"]:
                    expected *= 2.5 # Rare species thrive here
                    
            # Add noise
            count = int(random.gauss(expected, expected * 0.3))
            
            if count > 0:
                rows.append([
                    survey_id, site["id"], site["type"], year, date_str, 
                    sp, count, observer
                ])

# Write CSV
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["SurveyID", "Site", "SiteType", "Year", "Date", "CommonName", "Count", "Observer"])
    writer.writerows(rows)

print(f"Generated {len(rows)} survey records.")
PYEOF

python3 /tmp/create_bird_data.py "$CSV_PATH"
chown ga:ga "$CSV_PATH"

# Launch ONLYOFFICE with the CSV file
echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice_launch.log 2>&1 &"

# Wait for ONLYOFFICE window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
        echo "ONLYOFFICE window detected."
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 import -window root /tmp/wetland_bird_diversity_analysis_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="