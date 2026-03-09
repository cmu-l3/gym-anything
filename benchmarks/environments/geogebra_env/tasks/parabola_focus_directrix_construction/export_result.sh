#!/bin/bash
# Export script for Parabola Focus-Directrix Construction task
set -o pipefail

# Ensure fallback result on any failure
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
    "has_focus_point": false,
    "has_directrix_line": false,
    "has_locus_command": false,
    "has_annotation": false,
    "num_points": 0,
    "num_lines": 0,
    "num_commands": 0,
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

echo "=== Exporting Parabola Focus-Directrix Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python for robust analysis
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/parabola_locus.ggb"
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
    "has_focus_point": False,
    "focus_point_coords": [],
    "has_directrix_line": False,
    "directrix_line_y": None,
    "has_locus_command": False,
    "has_annotation": False,
    "num_points": 0,
    "num_lines": 0,
    "num_text_elements": 0,
    "num_commands": 0,
    "locus_count": 0,
    "xml_commands": []
}

# Search for the file (try expected path first, then recent .ggb files)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    candidates = sorted(
        glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True),
        key=os.path.getmtime, reverse=True
    )
    for c in candidates:
        mtime = os.path.getmtime(c)
        if TASK_START_TIME > 0 and int(mtime) >= TASK_START_TIME:
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

                # Count elements
                result["num_points"] = len(re.findall(r'<element type="point"', xml_content, re.IGNORECASE))
                result["num_lines"] = len(re.findall(r'<element type="line"', xml_content, re.IGNORECASE))
                result["num_text_elements"] = len(re.findall(r'<element type="text"', xml_content, re.IGNORECASE))

                # Extract all command names
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))
                result["num_commands"] = len(commands)

                # Check for Locus command
                locus_count = len(re.findall(r'<command name="Locus"', xml_content, re.IGNORECASE))
                result["locus_count"] = locus_count
                result["has_locus_command"] = locus_count > 0

                # Check for focus point near (0, 1): parse point coords
                # GeoGebra stores 2D points as: <coords x="0" y="1" z="1"/>
                # (homogeneous: actual coords are x/z, y/z)
                import xml.etree.ElementTree as ET
                try:
                    root = ET.fromstring(xml_content)
                    construction = root.find('.//construction')
                    if construction is not None:
                        for elem in construction.findall('element'):
                            etype = elem.get('type', '')
                            if etype == 'point':
                                coords = elem.find('coords')
                                if coords is not None:
                                    try:
                                        cx = float(coords.get('x', '0'))
                                        cy = float(coords.get('y', '0'))
                                        cz = float(coords.get('z', '1'))
                                        if abs(cz) > 1e-9:
                                            px = cx / cz
                                            py = cy / cz
                                        else:
                                            px, py = cx, cy
                                        result["focus_point_coords"].append({"x": px, "y": py})
                                        # Focus near (0, 1)?
                                        if abs(px) <= 0.15 and abs(py - 1.0) <= 0.15:
                                            result["has_focus_point"] = True
                                    except (ValueError, ZeroDivisionError):
                                        pass
                            elif etype == 'line':
                                # Check for directrix line y = -1
                                # Line coords in homogeneous: ax + by + c = 0
                                # For y = -1: 0x + 1y + 1 = 0, so coords x=0, y=1, z=1
                                coords = elem.find('coords')
                                if coords is not None:
                                    try:
                                        la = float(coords.get('x', '0'))
                                        lb = float(coords.get('y', '0'))
                                        lc = float(coords.get('z', '0'))
                                        # Horizontal line: |la| very small, lb != 0
                                        if abs(la) < 0.01 and abs(lb) > 0.01:
                                            # y-intercept = -lc/lb
                                            y_intercept = -lc / lb
                                            result["directrix_line_y"] = round(y_intercept, 4)
                                            if abs(y_intercept - (-1.0)) <= 0.15:
                                                result["has_directrix_line"] = True
                                    except (ValueError, ZeroDivisionError):
                                        pass
                except ET.ParseError as e:
                    result["xml_parse_error"] = str(e)

                # Check for annotation (text or distance measurement)
                has_text = result["num_text_elements"] > 0
                has_distance = bool(re.search(r'<element type="(distance|numeric|numericValue)"', xml_content, re.IGNORECASE))
                has_segment_len = bool(re.search(r'<command name="(Distance|Length|Segment)"', xml_content, re.IGNORECASE))
                result["has_annotation"] = has_text or has_distance or has_segment_len

    except zipfile.BadZipFile as e:
        result["zip_error"] = str(e)
    except Exception as e:
        result["xml_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(f"  file_found: {result['file_found']}")
print(f"  file_created_during_task: {result['file_created_during_task']}")
print(f"  has_focus_point: {result['has_focus_point']}")
print(f"  has_directrix_line: {result['has_directrix_line']}")
print(f"  has_locus_command: {result['has_locus_command']}")
print(f"  has_annotation: {result['has_annotation']}")
print(f"  commands: {result.get('xml_commands', [])}")
PYEOF

echo "=== Export Complete ==="
