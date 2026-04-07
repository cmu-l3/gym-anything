#!/bin/bash
echo "=== Exporting Cholera Toxin AB5 Architecture Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cholera_ab5_end_screenshot.png

# Compute ground truth contacts inside the container using PyMOL headless mode
cat > /tmp/compute_gt.pml << 'PMLEOF'
load /home/ga/PyMOL_Data/structures/1XTC.pdb, 1XTC
select anchor, chain A and resi 195-240
select bpentamer, chain B+C+D+E+F
select contacts, bpentamer within 4.0 of anchor

python
import json
gt_contacts = set()
def get_contact(chain, resi):
    gt_contacts.add(f"{chain}:{resi}")
cmd.iterate("contacts", "get_contact(chain, resi)")

with open("/tmp/cholera_gt.json", "w") as f:
    json.dump({"gt_contacts": sorted(list(gt_contacts))}, f)
python end
quit
PMLEOF

echo "Calculating ground truth contacts..."
pymol -qc /tmp/compute_gt.pml 2>/dev/null || true

# Gather agent result metrics
python3 << 'PYEOF'
import json, os

try:
    with open("/tmp/cholera_ab5_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/cholera_ab5.png"
report_path = "/home/ga/PyMOL_Data/cholera_interface_report.txt"

result = {}

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

with open("/tmp/cholera_ab5_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/cholera_ab5_result.json")
PYEOF

# Ensure verifier has permissions to copy files
chmod 644 /tmp/cholera_ab5_result.json /tmp/cholera_gt.json 2>/dev/null || true

echo "=== Export Complete ==="