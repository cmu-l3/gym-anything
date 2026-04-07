#!/bin/bash
echo "=== Exporting Biotin Electron Density Mesh Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/biotin_mesh_end_screenshot.png

SESSION_PATH="/home/ga/PyMOL_Data/sessions/biotin_density.pse"

# 1. Use PyMOL's headless mode to inspect the saved session file
# This reliably checks if volumetric map and mesh objects were successfully created
cat > /tmp/check_session.py << 'EOF'
import json
from pymol import cmd

try:
    cmd.load("/home/ga/PyMOL_Data/sessions/biotin_density.pse")
    objs = cmd.get_names("objects")
    types = {obj: cmd.get_type(obj) for obj in objs}
    res = {
        "has_map": "object:map" in types.values(),
        "has_mesh": "object:mesh" in types.values(),
        "types": types,
        "success": True
    }
except Exception as e:
    res = {
        "error": str(e),
        "has_map": False,
        "has_mesh": False,
        "success": False
    }

with open("/tmp/pse_data.json", "w") as f:
    json.dump(res, f)
cmd.quit()
EOF

if [ -f "$SESSION_PATH" ]; then
    # Run the headless PyMOL check as the ga user
    su - ga -c "DISPLAY=:1 pymol -cq /tmp/check_session.py" || true
else
    echo '{"has_map": false, "has_mesh": false, "success": false, "error": "No session file found"}' > /tmp/pse_data.json
fi

# 2. Collect all file metrics and combine with PyMOL analysis
python3 << 'PYEOF'
import json
import os

try:
    with open("/tmp/biotin_mesh_start_ts", "r") as f:
        TASK_START = int(f.read().strip())
except Exception:
    TASK_START = 0

fig_path = "/home/ga/PyMOL_Data/images/biotin_mesh.png"
report_path = "/home/ga/PyMOL_Data/density_report.txt"
session_path = "/home/ga/PyMOL_Data/sessions/biotin_density.pse"

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

# Check session file
if os.path.isfile(session_path):
    result["session_exists"] = True
    result["session_size_bytes"] = os.path.getsize(session_path)
    result["session_is_new"] = int(os.path.getmtime(session_path)) > TASK_START
else:
    result["session_exists"] = False
    result["session_size_bytes"] = 0
    result["session_is_new"] = False

# Check report file
if os.path.isfile(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()
else:
    result["report_exists"] = False
    result["report_content"] = ""

# Incorporate PyMOL session inspection data
if os.path.isfile("/tmp/pse_data.json"):
    try:
        with open("/tmp/pse_data.json", "r") as f:
            pse_data = json.load(f)
        result["session_data"] = pse_data
    except Exception:
        result["session_data"] = {"has_map": False, "has_mesh": False}
else:
    result["session_data"] = {"has_map": False, "has_mesh": False}

# Write final combined result
with open("/tmp/biotin_mesh_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result successfully written to /tmp/biotin_mesh_result.json")
PYEOF

echo "=== Export Complete ==="