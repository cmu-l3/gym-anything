#!/bin/bash
echo "=== Exporting SARS-CoV-2 N501Y Mutagenesis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/n501y_mutagenesis_end_screenshot.png

# Collect result data using Python heredoc for safe JSON generation
# and programmatic parsing of the agent's saved PDB file.
python3 << 'PYEOF'
import json
import os

TASK_START = int(open("/tmp/n501y_mutagenesis_start_ts").read().strip())

pdb_path = "/home/ga/PyMOL_Data/structures/6m0j_N501Y.pdb"
fig_path = "/home/ga/PyMOL_Data/images/n501y_interaction.png"
report_path = "/home/ga/PyMOL_Data/n501y_report.txt"

result = {
    "task_start_ts": TASK_START,
    "agent_pdb": {
        "exists": False,
        "size_bytes": 0,
        "is_new": False,
        "chainE_res501_name": None,
        "chainE_res500_CA_coord": None,
        "chainA_res41_CA_coord": None
    },
    "figure": {
        "exists": False,
        "size_bytes": 0,
        "is_new": False
    },
    "report": {
        "exists": False,
        "content": ""
    }
}

# 1. Inspect the agent's PDB
if os.path.isfile(pdb_path):
    result["agent_pdb"]["exists"] = True
    result["agent_pdb"]["size_bytes"] = os.path.getsize(pdb_path)
    result["agent_pdb"]["is_new"] = int(os.path.getmtime(pdb_path)) > TASK_START
    
    # Parse the PDB file to extract critical validation coordinates
    try:
        with open(pdb_path, 'r') as f:
            for line in f:
                if line.startswith("ATOM") or line.startswith("HETATM"):
                    # Strictly parse columns to avoid spacing issues
                    atom_name = line[12:16].strip()
                    res_name = line[17:20].strip()
                    chain = line[21]
                    try:
                        res_seq = int(line[22:26].strip())
                        x = float(line[30:38])
                        y = float(line[38:46])
                        z = float(line[46:54])
                    except ValueError:
                        continue
                        
                    if chain == 'E' and res_seq == 501 and atom_name == 'CA':
                        result["agent_pdb"]["chainE_res501_name"] = res_name
                        
                    if chain == 'E' and res_seq == 500 and atom_name == 'CA':
                        result["agent_pdb"]["chainE_res500_CA_coord"] = [x, y, z]
                        
                    if chain == 'A' and res_seq == 41 and atom_name == 'CA':
                        result["agent_pdb"]["chainA_res41_CA_coord"] = [x, y, z]
    except Exception as e:
        pass

# 2. Figure check
if os.path.isfile(fig_path):
    result["figure"]["exists"] = True
    result["figure"]["size_bytes"] = os.path.getsize(fig_path)
    result["figure"]["is_new"] = int(os.path.getmtime(fig_path)) > TASK_START

# 3. Report check
if os.path.isfile(report_path):
    result["report"]["exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report"]["content"] = f.read()

# Export JSON
output_json = "/tmp/sars_cov_2_n501y_result.json"
with open(output_json, "w") as f:
    json.dump(result, f, indent=2)

os.chmod(output_json, 0o666)
print(f"Result written to {output_json}")
PYEOF

echo "=== Export Complete ==="