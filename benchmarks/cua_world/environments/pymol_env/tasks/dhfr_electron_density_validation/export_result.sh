#!/bin/bash
echo "=== Exporting DHFR Electron Density Validation Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/dhfr_mtx_end_screenshot.png

# 1. Inspect the PyMOL session programmatically
# We run a headless PyMOL script to load the agent's .pse file and extract the objects inside.
cat > /tmp/inspect_session.py << 'EOF'
import json
import os
from pymol import cmd

session_path = "/home/ga/PyMOL_Data/sessions/dhfr_mtx_density.pse"
data = {
    "session_loaded": False,
    "objects": {},
    "mtx_atoms": 0,
    "error": None
}

if os.path.exists(session_path):
    try:
        # Load the user's session
        cmd.load(session_path)
        data["session_loaded"] = True
        
        # Enumerate all objects and their structural types (map, mesh, molecule, etc.)
        for obj in cmd.get_object_list():
            data["objects"][obj] = cmd.get_type(obj)
            
        # Count methotrexate atoms to ensure it's in the session
        data["mtx_atoms"] = cmd.count_atoms("resn MTX")
    except Exception as e:
        data["error"] = str(e)

with open("/tmp/session_inspection.json", "w") as f:
    json.dump(data, f)
EOF

# Run the inspection script securely inside PyMOL
su - ga -c "DISPLAY=:1 pymol -qc /tmp/inspect_session.py" 2>/dev/null || true

# 2. Compile all results into the final JSON payload
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/dhfr_mtx_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/dhfr_mtx_density.png"
report_path = "/home/ga/PyMOL_Data/dhfr_mtx_report.txt"
session_path = "/home/ga/PyMOL_Data/sessions/dhfr_mtx_density.pse"

result = {}

# File checks
for key, path in [("figure", fig_path), ("report", report_path), ("session", session_path)]:
    exists = os.path.isfile(path)
    result[f"{key}_exists"] = exists
    result[f"{key}_size_bytes"] = os.path.getsize(path) if exists else 0
    result[f"{key}_is_new"] = (int(os.path.getmtime(path)) > TASK_START) if exists else False

# Read report content
if result["report_exists"]:
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_content"] = ""

# Incorporate session inspection data
try:
    with open("/tmp/session_inspection.json", "r") as f:
        result["session_inspection"] = json.load(f)
except Exception:
    result["session_inspection"] = {"session_loaded": False, "objects": {}, "mtx_atoms": 0}

with open("/tmp/dhfr_mtx_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/dhfr_mtx_result.json")
PYEOF

echo "=== Export Complete ==="