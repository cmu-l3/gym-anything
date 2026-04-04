#!/bin/bash
# Export script for Audio Interference Nodal Analysis
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
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

echo "=== Exporting Audio Interference Result ==="

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time, math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/subwoofer_array.ggb"
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
    "speakers_correct": False,
    "wavelength_calc": False,
    "hyperbola_1_found": False,
    "hyperbola_2_found": False,
    "audience_line_found": False,
    "intersections_found": False,
    "num_hyperbolas": 0,
    "num_points": 0
}

# Find file
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
                
                # 1. Check Speakers at (-2,0) and (2,0)
                # Look for points with these coords
                # GeoGebra XML: <coords x="-2" y="0" z="1"/>
                has_s1 = bool(re.search(r'<coords x="-2(\.0+)?" y="0(\.0+)?" z="1"/>', xml_content))
                has_s2 = bool(re.search(r'<coords x="2(\.0+)?" y="0(\.0+)?" z="1"/>', xml_content))
                result["speakers_correct"] = has_s1 and has_s2

                # 2. Check Audience Line y = 5
                # Line equation: 0x + 1y - 5z = 0 -> coords x="0" y="1" z="-5"
                has_line = bool(re.search(r'<coords x="0(\.0+)?" y="1(\.0+)?" z="-5(\.0+)?"/>', xml_content))
                # Or explicitly defined as y=5 command
                has_line_cmd = "y = 5" in xml_content or "y=5" in xml_content
                result["audience_line_found"] = has_line or has_line_cmd

                # 3. Check Hyperbolas
                # Command: <command name="Hyperbola"> ... <input a0="..." a1="..." a2="1"/>
                # We expect major axis lengths of 1 and 3
                # Regex to find Hyperbola commands and their numeric inputs
                hyperbola_cmds = re.findall(r'<command name="Hyperbola">.*?</command>', xml_content, re.DOTALL)
                result["num_hyperbolas"] = len(hyperbola_cmds)
                
                for cmd in hyperbola_cmds:
                    # Input args are usually points and a number
                    # <input a0="A" a1="B" a2="1"/>
                    match = re.search(r'a2="([0-9.]+)"', cmd)
                    if match:
                        val = float(match.group(1))
                        if abs(val - 1.0) < 0.1:
                            result["hyperbola_1_found"] = True
                        elif abs(val - 3.0) < 0.1:
                            result["hyperbola_2_found"] = True
                
                # 4. Check Intersections/Dead Spots
                # Look for points defined by Intersect command
                intersect_cmds = re.findall(r'<command name="Intersect">', xml_content)
                # Or points on the line y=5 (roughly)
                # This is harder to check perfectly via regex, relying on Intersect command count
                # and point count
                result["intersections_found"] = len(intersect_cmds) >= 2 or result["num_points"] > 4 # 2 speakers + 2 or more intersections

                # 5. Check for wavelength calculation (optional evidence)
                if "340" in xml_content and "170" in xml_content:
                    result["wavelength_calc"] = True
                
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="