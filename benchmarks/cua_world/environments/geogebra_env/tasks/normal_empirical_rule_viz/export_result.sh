#!/bin/bash
# Export script for Normal Empirical Rule Visualization task
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": false,
    "task_start_time": 0,
    "task_end_time": 0,
    "has_normal_func": false,
    "has_integral": false,
    "integral_count": 0,
    "text_labels": [],
    "error": "Export script failed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Normal Empirical Rule Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python to analyze the .ggb file (ZIP archive containing XML)
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/normal_empirical_rule.ggb"
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
    "task_start_time": TASK_START_TIME,
    "task_end_time": int(time.time()),
    "has_normal_func": False,
    "normal_params": [],
    "has_integral": False,
    "integral_count": 0,
    "integral_bounds": [],
    "text_labels": [],
    "xml_commands": []
}

# Find the file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
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
    mtime = os.path.getmtime(found_file)
    result["file_modified"] = int(mtime)
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')

                # Extract commands
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))

                # Check for Normal distribution function
                # Can be via command: Normal(175.4, 7.2, x, false)
                # Or expression: exp(...)
                
                # Check command
                normal_cmds = re.findall(r'<command name="Normal">', xml_content, re.IGNORECASE)
                has_normal_cmd = len(normal_cmds) > 0
                
                # Check manual function definition (simplified check for exp and numbers)
                has_manual_func = False
                if not has_normal_cmd:
                    has_manual_func = bool(re.search(r'exp\s*\(.*175\.4', xml_content) and re.search(r'7\.2', xml_content))
                
                result["has_normal_func"] = has_normal_cmd or has_manual_func
                
                # Extract potential params if command used
                # This is tricky with regex, simplified to check existence of numbers in file
                if "175.4" in xml_content and "7.2" in xml_content:
                    result["normal_params"] = [175.4, 7.2]

                # Check for Integrals
                integral_cmds = re.findall(r'<command name="Integral">', xml_content, re.IGNORECASE)
                result["has_integral"] = len(integral_cmds) > 0
                result["integral_count"] = len(integral_cmds)
                
                # Extract integral bounds (input arguments)
                # <input a0="f" a1="168.2" a2="182.6"/>
                inputs = re.findall(r'<input [^>]*>', xml_content)
                bounds = []
                for inp in inputs:
                    # Look for numerical arguments that match our expected bounds
                    nums = re.findall(r'"(\d+\.?\d*)"', inp)
                    if nums:
                        bounds.extend([float(n) for n in nums])
                result["integral_bounds"] = bounds

                # Extract Text labels
                # <element type="text" label="text1"> ... <startPoint .../> ... </element>
                # The text content is usually in the "val" attribute of a child expression or command, 
                # OR in recent GeoGebra versions, it might be in `val` attribute of element if static.
                # Actually, static text is often in `label` or separate attributes.
                # Let's search for the expected percentage strings raw in the XML
                found_labels = []
                for label in ["68", "95", "99.7"]:
                    if label in xml_content:
                        found_labels.append(label)
                result["text_labels"] = found_labels

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="