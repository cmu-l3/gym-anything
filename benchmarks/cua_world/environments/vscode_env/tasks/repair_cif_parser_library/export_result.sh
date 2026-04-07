#!/bin/bash
set -e

echo "=== Exporting CIF Parser Result ==="

WORKSPACE_DIR="/home/ga/workspace/cif_parser"
RESULT_FILE="/tmp/cif_task_result.json"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check VSCode status
APP_RUNNING=$(pgrep -f "code" > /dev/null && echo "true" || echo "false")

# Save all VSCode files before evaluation
DISPLAY=:1 xdotool key ctrl+shift+s 2>/dev/null || true
sleep 1

# Execute a rigorous standalone validation script inside the container to prevent gaming.
# It directly imports the agent's modules and validates the bug fixes.
python3 << PYEXPORT
import json
import os
import sys

workspace = "$WORKSPACE_DIR"
sys.path.insert(0, workspace)

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "bug1_fixed": False,
    "bug2_fixed": False,
    "bug3_fixed": False,
    "bug4_fixed": False,
    "bug5_fixed": False,
    "errors": [],
    "files": {}
}

# 1. Export the file contents for verifier analysis
for fname in ["cif_parser/parser.py", "cif_parser/geometry.py"]:
    fpath = os.path.join(workspace, fname)
    if os.path.exists(fpath):
        with open(fpath, "r") as f:
            result["files"][fname] = {
                "content": f.read(),
                "mtime": os.path.getmtime(fpath)
            }
    else:
        result["files"][fname] = None

# 2. Run hidden tests against the agent's logic
try:
    from cif_parser.parser import clean_float, parse_metadata, parse_atoms
    from cif_parser.geometry import calculate_bond_distance
    
    # Bug 1: Uncertainty stripping
    try:
        val = clean_float("12.5(14)")
        if abs(val - 12.5) < 1e-6:
            result["bug1_fixed"] = True
    except Exception as e:
        result["errors"].append(f"Bug 1 Error: {e}")
        
    # Bug 2: Quote stripping
    try:
        content = "_symmetry_space_group_name_H-M 'P m -3 m'"
        meta = parse_metadata(content)
        if meta.get("_symmetry_space_group_name_H-M") == "P m -3 m":
            result["bug2_fixed"] = True
    except Exception as e:
        result["errors"].append(f"Bug 2 Error: {e}")
        
    # Bug 3: Dynamic columns
    try:
        content = '''loop_
_atom_site_type_symbol
_atom_site_fract_z
_atom_site_fract_y
_atom_site_fract_x
_atom_site_occupancy
O 0.789 0.456 0.123 1.0'''
        atoms = parse_atoms(content)
        if len(atoms) == 1 and atoms[0]['x'] == 0.123 and atoms[0]['y'] == 0.456 and atoms[0]['z'] == 0.789:
            result["bug3_fixed"] = True
    except Exception as e:
        result["errors"].append(f"Bug 3 Error: {e}")
        
    # Bug 4: Multiline Regex
    try:
        content = "_cell_length_a\n5.43\n_cell_length_b\n5.43"
        meta = parse_metadata(content)
        if meta.get("_cell_length_a") == "5.43" and meta.get("_cell_length_b") == "5.43":
            result["bug4_fixed"] = True
    except Exception as e:
        result["errors"].append(f"Bug 4 Error: {e}")
        
    # Bug 5: Periodic Boundaries
    try:
        a1 = {'x': 0.1, 'y': 0.9, 'z': 0.5}
        a2 = {'x': 0.9, 'y': 0.1, 'z': 0.5}
        dist = calculate_bond_distance(a1, a2, 10.0, 10.0, 10.0)
        # Should be sqrt(2^2 + 2^2 + 0^2) = 2.828427
        if abs(dist - 2.828427) < 1e-4:
            result["bug5_fixed"] = True
    except Exception as e:
        result["errors"].append(f"Bug 5 Error: {e}")
        
except Exception as e:
    result["errors"].append(f"Module Import Error: {e}")

# Save results
with open("$RESULT_FILE", "w") as out:
    json.dump(result, out, indent=2)

PYEXPORT

chmod 666 "$RESULT_FILE"
echo "Result saved to $RESULT_FILE"
echo "=== Export complete ==="