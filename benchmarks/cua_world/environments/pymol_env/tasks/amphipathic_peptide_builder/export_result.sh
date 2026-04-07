#!/bin/bash
echo "=== Exporting Peptide Builder Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/peptide_builder_end_screenshot.png

# Collect result data using Python heredoc for robust JSON generation and PDB parsing
python3 << 'PYEOF'
import json, os, math

# Read start time to verify file creation
try:
    TASK_START = int(open("/tmp/peptide_builder_start_ts").read().strip())
except:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/magainin_amphipathic.png"
pdb_path = "/home/ga/PyMOL_Data/magainin_ideal.pdb"
report_path = "/home/ga/PyMOL_Data/peptide_report.txt"

result = {}

# Check Image Output
if os.path.isfile(fig_path):
    result["figure_exists"] = True
    result["figure_size_bytes"] = os.path.getsize(fig_path)
    result["figure_is_new"] = int(os.path.getmtime(fig_path)) > TASK_START
else:
    result["figure_exists"] = False
    result["figure_size_bytes"] = 0
    result["figure_is_new"] = False

# Check Report Output
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Check PDB Output and Parse Coordinates
if os.path.isfile(pdb_path):
    result["pdb_exists"] = True
    result["pdb_size_bytes"] = os.path.getsize(pdb_path)
    result["pdb_is_new"] = int(os.path.getmtime(pdb_path)) > TASK_START
    
    seq_dict = {'ALA':'A', 'CYS':'C', 'ASP':'D', 'GLU':'E', 'PHE':'F', 'GLY':'G', 'HIS':'H', 'ILE':'I', 'LYS':'K', 'LEU':'L', 'MET':'M', 'ASN':'N', 'PRO':'P', 'GLN':'Q', 'ARG':'R', 'SER':'S', 'THR':'T', 'VAL':'V', 'TRP':'W', 'TYR':'Y'}
    
    residues = []
    ca_coords = {}
    current_res = None
    
    # Simple, fast PDB parser built-in
    with open(pdb_path, "r", errors="replace") as f:
        for line in f:
            if line.startswith("ATOM  ") or line.startswith("HETATM"):
                if len(line) < 54: continue
                atom_name = line[12:16].strip()
                res_name = line[17:20].strip()
                chain = line[21]
                try:
                    res_seq = int(line[22:26].strip())
                    x = float(line[30:38].strip())
                    y = float(line[38:46].strip())
                    z = float(line[46:54].strip())
                except ValueError:
                    continue
                
                res_id = (chain, res_seq)
                if res_id != current_res:
                    residues.append(seq_dict.get(res_name, 'X'))
                    current_res = res_id
                
                # Capture the CA atoms for distance calculation
                if atom_name == "CA" and res_id not in ca_coords:
                    ca_coords[res_id] = (x, y, z)
                    
    result["pdb_sequence"] = "".join(residues)
    
    # Calculate geometric distance from first to last CA atom
    if len(ca_coords) >= 2:
        # Sort by chain, then residue number
        sorted_res = sorted(ca_coords.keys(), key=lambda k: (k[0], k[1]))
        first = sorted_res[0]
        last = sorted_res[-1]
        c1 = ca_coords[first]
        c2 = ca_coords[last]
        dist = math.sqrt((c1[0]-c2[0])**2 + (c1[1]-c2[1])**2 + (c1[2]-c2[2])**2)
        result["ca_distance"] = dist
    else:
        result["ca_distance"] = None
else:
    result["pdb_exists"] = False
    result["pdb_size_bytes"] = 0
    result["pdb_is_new"] = False
    result["pdb_sequence"] = ""
    result["ca_distance"] = None

# Save results for verification
with open("/tmp/peptide_builder_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/peptide_builder_result.json")
PYEOF

echo "=== Export Complete ==="