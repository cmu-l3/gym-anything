#!/bin/bash
# Export script for Tensile Test Ramberg-Osgood Yield Strength task
# Analyzes the GeoGebra file and exports results to JSON
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo '{"error": "Export script failed", "file_found": false}' > /tmp/task_result.json
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Tensile Test Ramberg-Osgood Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Run Python analysis on the .ggb file
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/tensile_analysis.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_created_during_task": False,
    "num_points": 0,
    "has_data_points": False,
    "num_sliders": 0,
    "has_sliders": False,
    "slider_values": {},
    "has_power_expression": False,
    "has_function": False,
    "has_text_annotation": False,
    "num_text_elements": 0,
    "has_segments": False,
    "num_segments": 0,
    "command_list": [],
    "all_numeric_values": [],
    "point_coordinates": [],
    "candidate_E": None,
    "candidate_K": None,
    "candidate_n": None,
    "yield_point_x": None
}

# Find the file (check expected path, then search recent)
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
    mtime = int(os.path.getmtime(found_file))
    result["file_created_during_task"] = (mtime >= TASK_START_TIME)

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')

                # 1. Count points
                points = re.findall(r'<element type="point"', xml_content)
                result["num_points"] = len(points)
                result["has_data_points"] = len(points) >= 8

                # 2. Count segments (for residual lines)
                segments = re.findall(r'<element type="segment"', xml_content)
                result["num_segments"] = len(segments)
                result["has_segments"] = len(segments) >= 5

                # 3. Extract commands
                cmds = re.findall(r'<command name="([^"]+)"', xml_content)
                result["command_list"] = list(set(cmds))

                # 4. Check for function with power expression
                # Look for "^" in function definitions (Ramberg-Osgood has (x/K)^n)
                func_blocks = re.findall(r'<element type="function".*?</element>', xml_content, re.DOTALL)
                for block in func_blocks:
                    result["has_function"] = True
                    if '^' in block and '/' in block:
                        result["has_power_expression"] = True

                # Also check in <expression> tags and <command> definitions
                if not result["has_power_expression"]:
                    expressions = re.findall(r'<expression[^>]*label="[^"]*"[^>]*exp="([^"]*)"', xml_content)
                    for expr in expressions:
                        if '^' in expr and '/' in expr:
                            result["has_power_expression"] = True
                            result["has_function"] = True

                # 5. Check for text annotations
                text_elements = re.findall(r'<element type="text"', xml_content)
                result["num_text_elements"] = len(text_elements)
                result["has_text_annotation"] = len(text_elements) >= 1

                # 6. Extract all numeric values from sliders (heuristic parameter matching)
                try:
                    root = ET.fromstring(xml_content)
                    numeric_values = []

                    for elem in root.findall(".//element[@type='numeric']"):
                        label = elem.get('label', 'unknown')
                        val_child = elem.find("value")
                        if val_child is not None:
                            try:
                                val = float(val_child.get("val", 0))
                                numeric_values.append((label, val))
                            except:
                                pass
                        # Also check for slider child to count sliders
                        slider_child = elem.find("slider")
                        if slider_child is not None:
                            result["num_sliders"] += 1
                            try:
                                val_child2 = elem.find("value")
                                if val_child2 is not None:
                                    sval = float(val_child2.get("val", 0))
                                    result["slider_values"][label] = sval
                            except:
                                pass

                    # If empty, try regex backup
                    if not numeric_values:
                        matches = re.findall(r'<value\s+val="([\d\.\-eE]+)"', xml_content)
                        numeric_values = [("regex", float(m)) for m in matches]

                    result["all_numeric_values"] = [(l, v) for l, v in numeric_values]
                    result["has_sliders"] = result["num_sliders"] >= 2

                    # Heuristic: Find best candidate for E (target ~69000, range 50000-90000)
                    candidates_E = [v for l, v in numeric_values if 50000 <= v <= 90000]
                    if candidates_E:
                        result["candidate_E"] = min(candidates_E, key=lambda x: abs(x - 69000))

                    # Heuristic: Find best candidate for K (target ~450, range 300-900)
                    candidates_K = [v for l, v in numeric_values if 300 <= v <= 900]
                    if candidates_K:
                        result["candidate_K"] = min(candidates_K, key=lambda x: abs(x - 450))

                    # Heuristic: Find best candidate for n (target ~10, range 3-30)
                    candidates_n = [v for l, v in numeric_values if 3 <= v <= 30]
                    if candidates_n:
                        result["candidate_n"] = min(candidates_n, key=lambda x: abs(x - 10))

                    # 7. Extract point coordinates for yield point detection
                    # Look for points with x-coordinate in yield stress range (200-350 MPa)
                    for elem in root.findall(".//element[@type='point']"):
                        coords = elem.find("coords")
                        if coords is not None:
                            try:
                                px = float(coords.get("x", 0))
                                py = float(coords.get("y", 0))
                                pz = float(coords.get("z", 1))
                                # GeoGebra stores homogeneous coords: real_x = x/z, real_y = y/z
                                if abs(pz) > 0.001:
                                    real_x = px / pz
                                    real_y = py / pz
                                    result["point_coordinates"].append({"x": real_x, "y": real_y})
                                    # Check if this could be the yield point (x ~ 200-300 MPa)
                                    if 180 <= real_x <= 320 and 0.1 <= real_y <= 2.0:
                                        if result["yield_point_x"] is None or \
                                           abs(real_x - 242) < abs(result["yield_point_x"] - 242):
                                            result["yield_point_x"] = real_x
                            except:
                                pass

                except Exception as e:
                    result["xml_parse_error"] = str(e)

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Analysis complete.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="
cat /tmp/task_result.json
