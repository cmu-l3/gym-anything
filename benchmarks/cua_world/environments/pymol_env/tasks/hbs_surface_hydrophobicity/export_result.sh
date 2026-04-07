#!/bin/bash
echo "=== Exporting Sickle Cell Hemoglobin Surface Hydrophobicity Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Collect result data using Python heredoc for robust JSON generation and PDB parsing
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

pdb_path = "/home/ga/PyMOL_Data/structures/2HBS_hydrophobic.pdb"
fig_path = "/home/ga/PyMOL_Data/images/hbs_surface.png"
report_path = "/home/ga/PyMOL_Data/hbs_report.txt"

hydrophobic_resns = {"ALA", "VAL", "ILE", "LEU", "MET", "PHE", "TRP", "PRO", "TYR"}
polar_resns = {"ASP", "GLU", "ARG", "LYS", "HIS", "SER", "THR", "ASN", "GLN", "CYS"}

result = {
    "pdb_exists": False,
    "avg_b_hydro": 0.0,
    "avg_b_polar": 0.0,
    "report_exists": False,
    "report_content": "",
    "figure_exists": False,
    "figure_size_bytes": 0,
    "figure_is_new": False
}

# 1. PDB Check & Parsing
if os.path.isfile(pdb_path):
    result["pdb_exists"] = True
    b_hydro = []
    b_polar = []
    with open(pdb_path, "r", errors="replace") as f:
        for line in f:
            if line.startswith("ATOM  ") or line.startswith("HETATM"):
                resn = line[17:20].strip().upper()
                try:
                    b_factor = float(line[60:66].strip())
                except ValueError:
                    continue
                
                if resn in hydrophobic_resns:
                    b_hydro.append(b_factor)
                elif resn in polar_resns:
                    b_polar.append(b_factor)

    if b_hydro:
        result["avg_b_hydro"] = sum(b_hydro) / len(b_hydro)
    if b_polar:
        result["avg_b_polar"] = sum(b_polar) / len(b_polar)

# 2. Figure Check
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START

# 3. Report Check
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()

with open("/tmp/hbs_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/hbs_result.json")
PYEOF

echo "=== Export Complete ==="