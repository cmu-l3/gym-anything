#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Timber Cruise Inventory Analysis Task ==="

echo $(date +%s) > /tmp/timber_cruise_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/tmp/onlyoffice_test/Documents/Spreadsheets"
DOCS_DIR="/tmp/onlyoffice_test/Documents"
mkdir -p "$WORKSPACE_DIR"

# ============================
# Create Project Info
# ============================
cat > "$DOCS_DIR/project_info.txt" << 'EOF'
ELK CREEK UNIT - TIMBER CRUISE PARAMETERS
===================================================
Unit Name: Elk Creek
Tract Acreage: 240 acres
Cruise Type: Variable-Radius (Prism)
Basal Area Factor (BAF): 20
Number of Plots: 30
Date: March 10, 2026

MENSURATION FORMULAS & INSTRUCTIONS:
---------------------------------------------------
1. Tree Basal Area (sq ft) = 0.005454 * (DBH_inches)^2
2. Tree Expansion Factor (Trees Per Acre or TPA) = BAF / Tree Basal Area
3. Per-Tree Volume/Acre = TPA * Gross_Volume_BF
4. Net Volume = Gross_Volume_BF * (1 - Defect_Pct)
5. Tract Total Volume = (Sum of Net Volume/Acre) * Tract Acreage / Number of Plots

NOTE:
- The raw cruise data contains tree-level measurements.
- You must look up the Gross Volume (Board Feet) for each tree using the provided pnw_volume_table.csv. Match on Species, DBH, and Height.
- Prepare a professional summary showing TPA, Basal Area, and Net Volume per acre by SPECIES and by DBH CLASS.
- Conclude with the Total Tract Net Volume (in Board Feet or MBF).
EOF

# ============================
# Python script to generate Cruise Data & Volume Table
# ============================
cat > /tmp/create_timber_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
import os

random.seed(2026)

cruise_path = "/tmp/onlyoffice_test/Documents/Spreadsheets/elk_creek_cruise.csv"
vol_path = "/tmp/onlyoffice_test/Documents/Spreadsheets/pnw_volume_table.csv"

species_list = ["DF", "WH", "WRC", "RA", "BM"]
species_weights = [0.45, 0.25, 0.15, 0.10, 0.05]
species_factors = {"DF": 1.0, "WH": 0.95, "WRC": 0.85, "RA": 0.80, "BM": 0.75}

# Generate Volume Table
vol_headers = ["Species", "DBH_Class", "Height_Class", "Gross_Volume_BF"]
vol_data = []

dbh_classes = list(range(8, 54, 2))
ht_classes = list(range(40, 220, 10))

for sp in species_list:
    for dbh in dbh_classes:
        for ht in ht_classes:
            # Simple volume approximation (Scribner-ish)
            vol = int((dbh**2 * ht) * 0.015 * species_factors[sp])
            if vol > 0:
                vol_data.append([sp, dbh, ht, vol])

with open(vol_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(vol_headers)
    writer.writerows(vol_data)


# Generate Cruise Data
cruise_headers = ["Plot_ID", "Tree_Num", "Species", "DBH_inches", "Total_Height_ft", "Tree_Class", "Defect_Pct", "Crown_Ratio"]
cruise_data = []

# Generate 30 plots
for plot in range(1, 31):
    # Base trees per plot based on BAF 20. Avg ~15 trees
    num_trees = int(random.gauss(16, 4))
    num_trees = max(5, min(30, num_trees))
    
    for tree in range(1, num_trees + 1):
        sp = random.choices(species_list, weights=species_weights)[0]
        
        # Determine DBH
        dbh = int(random.gauss(20, 8))
        if dbh % 2 != 0: dbh += 1 # round to even classes
        dbh = max(8, min(52, dbh))
        
        # Determine Height based on DBH
        ht_base = 40 + (dbh * 3.5)
        ht = int(random.gauss(ht_base, 15))
        ht = round(ht / 10) * 10 # round to nearest 10
        ht = max(40, min(210, ht))
        
        tree_class = random.choices([1, 2, 3], weights=[0.85, 0.10, 0.05])[0]
        
        defect = 0
        if tree_class == 2:
            defect = round(random.uniform(0.05, 0.40), 2)
        elif tree_class == 3:
            defect = round(random.uniform(0.30, 0.90), 2)
            
        crown = round(random.uniform(0.2, 0.7), 2)
        
        cruise_data.append([plot, tree, sp, dbh, ht, tree_class, defect, crown])

with open(cruise_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(cruise_headers)
    writer.writerows(cruise_data)

PYEOF

python3 /tmp/create_timber_data.py
# chown -R ga:ga "$WORKSPACE_DIR" "$DOCS_DIR/project_info.txt"

# Take initial screenshot of desktop
sh -c "DISPLAY=:1 scrot /tmp/timber_cruise_initial.png" 2>/dev/null || true

echo "=== Setup Complete ==="