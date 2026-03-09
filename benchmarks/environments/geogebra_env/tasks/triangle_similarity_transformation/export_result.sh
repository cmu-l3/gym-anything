#!/bin/bash
# Export script for Triangle Similarity Transformation task
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
    "has_original_triangle": false,
    "original_vertices_correct": false,
    "has_dilation": false,
    "has_measurements": false,
    "has_annotation": false,
    "num_polygons": 0,
    "num_points": 0,
    "num_segments": 0,
    "num_text_elements": 0,
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

echo "=== Exporting Triangle Similarity Transformation Result ==="

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/triangle_similarity.ggb"
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
    "has_original_triangle": False,
    "original_vertices_correct": False,
    "has_dilation": False,
    "has_measurements": False,
    "has_annotation": False,
    "num_polygons": 0,
    "num_points": 0,
    "num_segments": 0,
    "num_text_elements": 0,
    "xml_commands": [],
    "point_coords": []
}

# Expected vertices
A = (0.0, 0.0)
B = (4.0, 0.0)
C = (2.0, 3.0)
TOL = 0.15

def point_matches(px, py, ex, ey):
    return abs(px - ex) <= TOL and abs(py - ey) <= TOL

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

                result["num_polygons"] = len(re.findall(r'<element type="polygon"', xml_content, re.IGNORECASE))
                result["num_points"] = len(re.findall(r'<element type="point"', xml_content, re.IGNORECASE))
                result["num_segments"] = len(re.findall(r'<element type="segment"', xml_content, re.IGNORECASE))
                result["num_text_elements"] = len(re.findall(r'<element type="text"', xml_content, re.IGNORECASE))

                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))

                # Check for Dilation/Dilate command
                result["has_dilation"] = bool(re.search(
                    r'<command name="(Dilate|Dilation|DilateFromPoint)"',
                    xml_content, re.IGNORECASE
                ))

                # Check for measurements (Distance, Length, Segment length display)
                has_dist_cmd = bool(re.search(r'<command name="(Distance|Length)"', xml_content, re.IGNORECASE))
                # Also check for numeric value elements that show segment lengths
                has_numeric = len(re.findall(r'<element type="numeric(Value)?"', xml_content, re.IGNORECASE)) >= 3
                result["has_measurements"] = has_dist_cmd or has_numeric or result["num_segments"] >= 6

                # Check for text annotation
                result["has_annotation"] = result["num_text_elements"] >= 1

                # Parse points to check for original triangle vertices
                try:
                    root_xml = ET.fromstring(xml_content)
                    all_points = []
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
                                    all_points.append({"x": round(px, 4), "y": round(py, 4)})
                                except (ValueError, ZeroDivisionError):
                                    pass
                    result["point_coords"] = all_points

                    # Check if original vertices A(0,0), B(4,0), C(2,3) are present
                    found_A = any(point_matches(p["x"], p["y"], *A) for p in all_points)
                    found_B = any(point_matches(p["x"], p["y"], *B) for p in all_points)
                    found_C = any(point_matches(p["x"], p["y"], *C) for p in all_points)
                    result["original_vertices_correct"] = found_A and found_B and found_C
                    result["has_original_triangle"] = result["num_polygons"] >= 1 or result["num_segments"] >= 3

                    # Check for dilated vertices: A'=(0,0), B'=(6,0), C'=(3,4.5)
                    SCALE = 1.5
                    Ap = (A[0]*SCALE, A[1]*SCALE)  # (0, 0) — same as A
                    Bp = (B[0]*SCALE, B[1]*SCALE)  # (6, 0)
                    Cp = (C[0]*SCALE, C[1]*SCALE)  # (3, 4.5)
                    found_Bp = any(point_matches(p["x"], p["y"], *Bp) for p in all_points)
                    found_Cp = any(point_matches(p["x"], p["y"], *Cp) for p in all_points)
                    result["has_dilated_triangle"] = found_Bp and found_Cp
                    result["dilated_B_found"] = found_Bp
                    result["dilated_C_found"] = found_Cp

                except ET.ParseError as e:
                    result["xml_parse_error"] = str(e)

    except zipfile.BadZipFile as e:
        result["zip_error"] = str(e)
    except Exception as e:
        result["xml_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(f"  file_found: {result['file_found']}")
print(f"  file_created_during_task: {result['file_created_during_task']}")
print(f"  original_vertices_correct: {result['original_vertices_correct']}")
print(f"  has_dilation: {result['has_dilation']}")
print(f"  has_dilated_triangle: {result.get('has_dilated_triangle', False)}")
print(f"  has_measurements: {result['has_measurements']}")
print(f"  has_annotation: {result['has_annotation']}")
print(f"  commands: {result.get('xml_commands', [])}")
PYEOF

echo "=== Export Complete ==="
