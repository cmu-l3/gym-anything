#!/bin/bash
echo "=== Exporting PROTAC Ternary Complex Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/protac_end_screenshot.png

# Collect result data and compute ground truth using headless PyMOL
python3 << 'PYEOF'
import json
import os
import pymol
from pymol import cmd

# Start PyMOL without GUI
pymol.finish_launching(['pymol', '-qc'])

TASK_START = int(open("/tmp/protac_start_ts").read().strip())

fig_path = "/home/ga/PyMOL_Data/images/protac_complex.png"
report_path = "/home/ga/PyMOL_Data/protac_report.txt"

result = {}

# Check Agent's Figure
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check Agent's Report
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Compute Ground Truth dynamically inside the container
try:
    cmd.set("fetch_path", "/tmp")
    cmd.fetch("5T35")
    
    neo_residues = set()
    cmd.iterate("chain D and (chain D within 4.0 of chain A)", "neo_residues.add(resi)")
    
    lig_residues = set()
    cmd.iterate("chain D and (chain D within 4.0 of resn MZ1)", "lig_residues.add(resi)")
    
    result["gt_neo_count"] = len(neo_residues)
    result["gt_lig_count"] = len(lig_residues)
    result["gt_success"] = True
except Exception as e:
    result["gt_success"] = False
    result["gt_error"] = str(e)
    # Fallback to known ground truth for 5T35 if computation fails
    result["gt_neo_count"] = 16 
    result["gt_lig_count"] = 24 

with open("/tmp/protac_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/protac_result.json")
PYEOF

echo "=== Export Complete ==="