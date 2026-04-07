#!/bin/bash
echo "=== Setting up PTEN Cancer Mutation Mapping ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp to prevent gaming
rm -f /home/ga/PyMOL_Data/images/pten_mutations.png
rm -f /home/ga/PyMOL_Data/pten_mutation_report.txt
rm -f /tmp/pten_ground_truth.json

# Record task start timestamp (integer seconds)
date +%s > /tmp/pten_mutation_start_ts

# Download PDB secretly to compute ground truth
wget -q "https://files.rcsb.org/download/1D5R.pdb" -O "/tmp/1D5R_gt.pdb" 2>/dev/null

# Compute exact ground truth distances headlessly using python
python3 << 'PYEOF'
import json, math, os

pdb_file = "/tmp/1D5R_gt.pdb"
coords = {}

if os.path.exists(pdb_file):
    with open(pdb_file, "r") as f:
        for line in f:
            if line.startswith("ATOM  ") and line[13:16] == "CA " and line[21] == "A":
                try:
                    resi = int(line[22:26].strip())
                    x = float(line[30:38].strip())
                    y = float(line[38:46].strip())
                    z = float(line[46:54].strip())
                    coords[resi] = (x, y, z)
                except:
                    pass

gt = {}
if 124 in coords:
    c124 = coords[124]
    for r in [129, 130, 211, 331]:
        if r in coords:
            tgt = coords[r]
            dist = math.sqrt((c124[0]-tgt[0])**2 + (c124[1]-tgt[1])**2 + (c124[2]-tgt[2])**2)
            gt[str(r)] = round(dist, 2)

with open("/tmp/pten_ground_truth.json", "w") as f:
    json.dump(gt, f)

PYEOF
chmod 644 /tmp/pten_ground_truth.json
rm -f /tmp/1D5R_gt.pdb

# Launch PyMOL with no structures loaded (agent must fetch)
launch_pymol

sleep 2
take_screenshot /tmp/pten_mutation_start_screenshot.png

echo "=== Setup Complete ==="