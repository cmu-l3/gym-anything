#!/bin/bash
# Export script for Cam Profile Design task
set -o pipefail

# Trap to ensure result file creation
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_created_during_task": false,
    "has_curve_command": false,
    "has_if_command": false,
    "has_trig_functions": false,
    "xml_commands": [],
    "screenshot_path": "",
    "error": "Export script failed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Cam Profile Result ==="

# 1. Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 2. Python script to analyze the GGB file (ZIP + XML parsing)
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/cam_profile.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "has_curve_command": False,
    "has_if_command": False,
    "has_trig_functions": False,
    "base_radius_defined": False,
    "lift_defined": False,
    "xml_commands": [],
    "screenshot_path": "/tmp/task_final.png"
}

# Find file (expected path or recent backup)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Look for any recent GGB file in the folder
    candidates = sorted(
        glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True),
        key=os.path.getmtime, reverse=True
    )
    for c in candidates:
        if TASK_START_TIME > 0 and int(os.path.getmtime(c)) >= TASK_START_TIME:
            found_file = c
            break

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    result["file_size"] = os.path.getsize(found_file)
    mtime = int(os.path.getmtime(found_file))
    result["file_modified"] = mtime
    result["file_created_during_task"] = mtime >= TASK_START_TIME

    # Parse XML content
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Extract used commands
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))
                
                # Check for key commands required for this task
                # Curve command (parametric)
                if any(c.lower() == 'curve' or c.lower() == 'curvecartesian' for c in result["xml_commands"]):
                    result["has_curve_command"] = True
                
                # If command (for piecewise logic)
                if any(c.lower() == 'if' for c in result["xml_commands"]):
                    result["has_if_command"] = True
                
                # Check for Trigonometry (sin/cos) in expressions
                # Expressions are often in 'val' attributes or <expression> tags
                if re.search(r'(sin|cos)\(', xml_content, re.IGNORECASE):
                    result["has_trig_functions"] = True
                
                # Check for constants (rough heuristic)
                if re.search(r'val="3"', xml_content) or re.search(r'val="3\.0"', xml_content):
                    result["base_radius_defined"] = True
                if re.search(r'val="2"', xml_content) or re.search(r'val="2\.0"', xml_content):
                    result["lift_defined"] = True

    except Exception as e:
        print(f"Error parsing GGB file: {e}")

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"