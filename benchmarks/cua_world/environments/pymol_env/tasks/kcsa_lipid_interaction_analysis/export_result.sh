#!/bin/bash
echo "=== Exporting KcsA Lipid Interaction Analysis Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/kcsa_lipid_end_screenshot.png

# Calculate ground truth distances using PyMOL in headless mode
cat > /tmp/calc_dist.py << 'EOF'
import json
from pymol import cmd

try:
    cmd.load("/home/ga/PyMOL_Data/structures/1K4C.pdb")
    dist64 = cmd.distance("d64", "resn DGA", "chain C and resi 64")
    dist89 = cmd.distance("d89", "resn DGA", "chain C and resi 89")
except Exception as e:
    dist64 = 5.2 # fallback approximation if script fails
    dist89 = 2.9 # fallback approximation if script fails

with open("/tmp/gt_distances.json", "w") as f:
    json.dump({"dist64": float(dist64), "dist89": float(dist89)}, f)
EOF

# Run headless pymol
su - ga -c "DISPLAY=:1 pymol -qc /tmp/calc_dist.py"

python3 << 'PYEOF'
import json, os

try:
    TASK_START = int(open("/tmp/kcsa_lipid_start_ts").read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/kcsa_lipid.png"
report_path = "/home/ga/PyMOL_Data/kcsa_lipid_report.txt"

result = {}

# Figure check
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Report check
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Load Ground Truth
try:
    with open("/tmp/gt_distances.json", "r") as f:
        gt = json.load(f)
        result["gt_dist64"] = gt.get("dist64", 5.2)
        result["gt_dist89"] = gt.get("dist89", 2.9)
except Exception:
    result["gt_dist64"] = 5.2
    result["gt_dist89"] = 2.9

with open("/tmp/kcsa_lipid_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/kcsa_lipid_result.json")
PYEOF

echo "=== Export Complete ==="