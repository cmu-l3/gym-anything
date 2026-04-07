#!/bin/bash
echo "=== Exporting MBP Conformational Morph Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/mbp_morph_end_screenshot.png

python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/mbp_morph_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except:
    TASK_START = 0

pdb_path = "/home/ga/PyMOL_Data/mbp_morph.pdb"
fig_path = "/home/ga/PyMOL_Data/images/mbp_superposition.png"
report_path = "/home/ga/PyMOL_Data/mbp_morph_report.txt"

result = {}

# 1. Image Check
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# 2. Report Check
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# 3. Morph PDB trajectory check
if os.path.isfile(pdb_path):
    result["pdb_exists"] = True
    result["pdb_is_new"] = int(os.path.getmtime(pdb_path)) > TASK_START
    
    models = 0
    atoms_first = 0
    atoms_last = 0
    current_atoms = 0
    
    with open(pdb_path, "r", errors="replace") as f:
        for line in f:
            if line.startswith("MODEL"):
                if models == 1:
                    atoms_first = current_atoms
                current_atoms = 0
                models += 1
            elif line.startswith("ATOM") or line.startswith("HETATM"):
                current_atoms += 1
                
    if models > 0:
        atoms_last = current_atoms
        if models == 1:
            atoms_first = current_atoms
    elif current_atoms > 0: 
        # File has atoms but no MODEL tags (single state)
        models = 1
        atoms_first = current_atoms
        atoms_last = current_atoms

    result["pdb_models"] = models
    result["pdb_atoms_first"] = atoms_first
    result["pdb_atoms_last"] = atoms_last
else:
    result["pdb_exists"] = False
    result["pdb_is_new"] = False
    result["pdb_models"] = 0
    result["pdb_atoms_first"] = 0
    result["pdb_atoms_last"] = 0

with open("/tmp/mbp_morph_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/mbp_morph_result.json")
PYEOF

echo "=== Export Complete ==="