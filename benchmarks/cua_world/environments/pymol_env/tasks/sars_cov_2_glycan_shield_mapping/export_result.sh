#!/bin/bash
echo "=== Exporting SARS-CoV-2 Glycan Shield Mapping Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of the application state
take_screenshot /tmp/sars_cov_2_end_screenshot.png

# Create a Python script to run in PyMOL headless mode
# This fetches an independent copy of 6VXX to dynamically calculate the ground truth NAG count.
cat > /tmp/compute_gt.py << 'GT_EOF'
import cmd, json, os

# Suppress PyMOL output
cmd.feedback("disable", "all", "everything")

try:
    # Fetch 6VXX independently
    cmd.fetch("6VXX", "gt_6VXX")
    
    total_nag = set()
    chainA_nag = set()
    chainB_nag = set()

    def count_nag(chain, resi):
        total_nag.add((chain, resi))
        if chain == 'A': chainA_nag.add((chain, resi))
        if chain == 'B': chainB_nag.add((chain, resi))

    # Iterate over all NAG residues to count unique ones (each residue has multiple atoms)
    cmd.iterate("gt_6VXX and resn NAG", "count_nag(chain, resi)", space={'count_nag': count_nag, 'total_nag': total_nag, 'chainA_nag': chainA_nag, 'chainB_nag': chainB_nag})

    gt = {
        "total_nag": len(total_nag),
        "chainA_nag": len(chainA_nag),
        "chainB_nag": len(chainB_nag)
    }
except Exception as e:
    # Fallback if network fetch fails during evaluation
    gt = {"total_nag": -1, "chainA_nag": -1, "chainB_nag": -1}

# Evaluate agent's outputs
try:
    with open("/tmp/sars_cov_2_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/glycan_shield.png"
report_path = "/home/ga/PyMOL_Data/glycan_report.txt"

result = {"ground_truth": gt}

# Check figure
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check report
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

with open("/tmp/sars_cov_2_result.json", "w") as f:
    json.dump(result, f, indent=2)

cmd.quit()
GT_EOF

echo "Computing ground truth via PyMOL headless..."
pymol -qc /tmp/compute_gt.py

echo "Result written to /tmp/sars_cov_2_result.json"
echo "=== Export Complete ==="