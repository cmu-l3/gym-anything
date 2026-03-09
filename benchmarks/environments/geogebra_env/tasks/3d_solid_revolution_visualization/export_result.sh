#!/bin/bash
# Export script for 3D Solid of Revolution Visualization task
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
    "has_3d_view": false,
    "has_sqrt_function": false,
    "has_surface_command": false,
    "has_slider": false,
    "has_volume_text": false,
    "num_sliders": 0,
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

echo "=== Exporting 3D Solid of Revolution Result ==="

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/solid_revolution.ggb"
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
    "has_3d_view": False,
    "has_sqrt_function": False,
    "has_surface_command": False,
    "has_slider": False,
    "has_volume_text": False,
    "has_circle_cross_section": False,
    "num_sliders": 0,
    "num_text_elements": 0,
    "num_3d_elements": 0,
    "xml_commands": [],
    "surface_expression": ""
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
            # Check for geogebra3d.xml or references to 3D in geogebra.xml
            file_list = z.namelist()
            has_3d_file = 'geogebra3d.xml' in file_list

            if 'geogebra.xml' in file_list:
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
            else:
                xml_content = ""

            # Try to also read 3D XML
            xml_3d = ""
            if has_3d_file:
                xml_3d = z.read('geogebra3d.xml').decode('utf-8', errors='replace')

            combined_xml = xml_content + xml_3d

            # Count element types
            result["num_sliders"] = len(re.findall(r'<element type="slider"', combined_xml, re.IGNORECASE))
            result["num_text_elements"] = len(re.findall(r'<element type="text"', combined_xml, re.IGNORECASE))

            # Count 3D-specific elements
            result["num_3d_elements"] = len(re.findall(
                r'<element type="(surface3d|quadric|net|polyhedron|cone3d|cylinder3d|plane3d|conicsection3d)"',
                combined_xml, re.IGNORECASE
            ))

            # Check for 3D view
            result["has_3d_view"] = (
                has_3d_file or
                bool(re.search(r'euclidianView3D|<view\s[^>]*3d|3DGraphics', combined_xml, re.IGNORECASE)) or
                result["num_3d_elements"] > 0
            )

            # Extract all command names
            commands = re.findall(r'<command name="([^"]+)"', combined_xml)
            result["xml_commands"] = list(set(commands))

            # Check for Surface command (parametric surface for solid of revolution)
            result["has_surface_command"] = bool(re.search(
                r'<command name="Surface"',
                combined_xml, re.IGNORECASE
            ))

            # Also check for other solid commands
            has_rotate_surface = bool(re.search(
                r'<command name="(Rotate|RotateSurface|Cone|Cylinder|Sphere)"',
                combined_xml, re.IGNORECASE
            ))
            if not result["has_surface_command"]:
                result["has_surface_command"] = has_rotate_surface

            # Check for sqrt function in the construction
            sqrt_patterns = [r'sqrt\s*\(', r'√', r'x\^0\.5', r'x\^\(1/2\)', r'x\^\.5']
            result["has_sqrt_function"] = any(
                re.search(p, combined_xml, re.IGNORECASE) for p in sqrt_patterns
            )

            # Check for slider
            result["has_slider"] = result["num_sliders"] >= 1

            # Check for circle/cross-section
            result["has_circle_cross_section"] = bool(re.search(
                r'<command name="(Circle|Ellipse|CircleSector)"',
                combined_xml, re.IGNORECASE
            ))

            # Extract Surface command expression for verification
            surf_match = re.search(r'<command name="Surface".*?</command>', combined_xml, re.DOTALL | re.IGNORECASE)
            if surf_match:
                expr_in_surf = re.findall(r'<input a\d+="([^"]*)"', surf_match.group())
                if expr_in_surf:
                    result["surface_expression"] = "; ".join(expr_in_surf[:3])

            # Check for volume text (pi or integral reference in text elements)
            text_matches = re.findall(r'<element type="text"[^>]*>.*?</element>', combined_xml, re.DOTALL | re.IGNORECASE)
            volume_keywords = ['pi', 'π', 'volume', 'vol', 'integral', '25.13', '8π', '8pi', 'a^2', 'a²']
            for txt_elem in text_matches:
                if any(kw in txt_elem.lower() for kw in volume_keywords):
                    result["has_volume_text"] = True
                    break
            # Also accept any text element (the annotation shows formula)
            if not result["has_volume_text"] and result["num_text_elements"] >= 1:
                result["has_volume_text"] = True  # more lenient: any text annotation

    except zipfile.BadZipFile as e:
        result["zip_error"] = str(e)
    except Exception as e:
        result["xml_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(f"  file_found: {result['file_found']}")
print(f"  file_created_during_task: {result['file_created_during_task']}")
print(f"  has_3d_view: {result['has_3d_view']}")
print(f"  has_sqrt_function: {result['has_sqrt_function']}")
print(f"  has_surface_command: {result['has_surface_command']}")
print(f"  has_slider: {result['has_slider']}")
print(f"  has_volume_text: {result['has_volume_text']}")
print(f"  num_3d_elements: {result['num_3d_elements']}")
print(f"  commands: {result.get('xml_commands', [])}")
PYEOF

echo "=== Export Complete ==="
