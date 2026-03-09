#!/bin/bash
# Export script for Calculus Derivative Exploration task
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
    "has_cubic_function": false,
    "has_derivative": false,
    "has_tangent": false,
    "has_slider_or_draggable": false,
    "has_critical_points": false,
    "num_functions": 0,
    "num_sliders": 0,
    "num_points": 0,
    "xml_commands": [],
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

echo "=== Exporting Calculus Derivative Exploration Result ==="

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/derivative_explorer.ggb"
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
    "has_cubic_function": False,
    "function_expression": "",
    "has_derivative": False,
    "has_tangent": False,
    "has_slider_or_draggable": False,
    "has_critical_points": False,
    "num_functions": 0,
    "num_sliders": 0,
    "num_points": 0,
    "num_text_elements": 0,
    "xml_commands": [],
    "critical_point_coords": []
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

                # Count element types
                result["num_functions"] = len(re.findall(r'<element type="function"', xml_content, re.IGNORECASE))
                result["num_sliders"] = len(re.findall(r'<element type="slider"', xml_content, re.IGNORECASE))
                result["num_points"] = len(re.findall(r'<element type="point"', xml_content, re.IGNORECASE))
                result["num_text_elements"] = len(re.findall(r'<element type="text"', xml_content, re.IGNORECASE))

                # Extract all command names
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))

                # Check for cubic function: x^3 or x³
                # Look in function expressions
                # GeoGebra stores expressions in <expression label="f" exp="x^3 - 3x + 1" .../>
                # or in <element type="function"> with nested <expression> or value
                cubic_patterns = [
                    r'x\^3', r'x³', r'x\*x\*x',
                    r'3\s*\*\s*x\s*\+\s*1',  # partial match
                ]
                full_xml_lower = xml_content.lower()
                has_cubic = any(re.search(p, xml_content, re.IGNORECASE) for p in cubic_patterns)
                result["has_cubic_function"] = has_cubic

                # Try to find the function expression
                expr_matches = re.findall(r'exp="([^"]*x[^"]*)"', xml_content)
                for e in expr_matches:
                    if 'x^3' in e or 'x³' in e or ('x' in e and '3' in e):
                        result["function_expression"] = e
                        break

                # Check for Derivative command
                result["has_derivative"] = bool(re.search(r'<command name="Derivative"', xml_content, re.IGNORECASE))
                # Also check for f' notation in expressions (indicates derivative was computed)
                if not result["has_derivative"]:
                    result["has_derivative"] = bool(re.search(r"f'\(x\)|f'|Derivative", xml_content))

                # Check for Tangent command
                result["has_tangent"] = bool(re.search(r'<command name="Tangent"', xml_content, re.IGNORECASE))

                # Check for slider or a point constrained to curve (draggable)
                has_slider = result["num_sliders"] > 0
                # A point on a function curve: <command name="PointIn"> or <command name="Point">
                # with a function argument, or a point with input referencing f
                has_point_on_curve = bool(re.search(
                    r'<command name="(PointIn|Point)">\s*<input a0="[fghF]"',
                    xml_content, re.IGNORECASE
                ))
                result["has_slider_or_draggable"] = has_slider or has_point_on_curve

                # Check for critical points near x=-1 and x=1
                # Extremum command or Root command on derivative, or manually placed points
                has_extremum = bool(re.search(r'<command name="(Extremum|Root|Roots)"', xml_content, re.IGNORECASE))

                import xml.etree.ElementTree as ET
                try:
                    root_xml = ET.fromstring(xml_content)
                    critical_pts = []
                    for elem in root_xml.iter('element'):
                        if elem.get('type') == 'point':
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    cx = float(coords.get('x', '0'))
                                    cy = float(coords.get('y', '0'))
                                    cz = float(coords.get('z', '1'))
                                    if abs(cz) > 1e-9:
                                        px, py = cx/cz, cy/cz
                                    else:
                                        px, py = cx, cy
                                    # Check if near critical points (-1, 3) or (1, -1)
                                    if abs(px - (-1.0)) <= 0.15 or abs(px - 1.0) <= 0.15:
                                        critical_pts.append({"x": round(px, 3), "y": round(py, 3)})
                                except (ValueError, ZeroDivisionError):
                                    pass
                    result["critical_point_coords"] = critical_pts
                    result["has_critical_points"] = has_extremum or len(critical_pts) >= 1
                except ET.ParseError:
                    result["has_critical_points"] = has_extremum

    except zipfile.BadZipFile as e:
        result["zip_error"] = str(e)
    except Exception as e:
        result["xml_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(f"  file_found: {result['file_found']}")
print(f"  file_created_during_task: {result['file_created_during_task']}")
print(f"  has_cubic_function: {result['has_cubic_function']}")
print(f"  has_derivative: {result['has_derivative']}")
print(f"  has_tangent: {result['has_tangent']}")
print(f"  has_slider_or_draggable: {result['has_slider_or_draggable']}")
print(f"  has_critical_points: {result['has_critical_points']}")
print(f"  commands: {result.get('xml_commands', [])}")
PYEOF

echo "=== Export Complete ==="
