#!/bin/bash
# Export script for Traffic Green Wave Visualization
# Extracts XML from .ggb file and parses it for scoring elements
set -o pipefail

# Ensure fallback result on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_slider": false,
    "has_sequence": false,
    "has_intersections": false,
    "has_car_trajectory": false,
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

echo "=== Exporting Traffic Green Wave Result ==="

# 1. Capture final visual state for VLM
take_screenshot /tmp/task_end_screenshot.png

# 2. Analyze GeoGebra file using Python
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time

EXPECTED_PATH = "/home/ga/Documents/GeoGebra/projects/green_wave.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "task_end_time": int(time.time()),
    "has_slider": False,
    "slider_label": "",
    "has_sequence": False,
    "sequence_count": 0,
    "has_car_trajectory": False,
    "car_slope": 0.0,
    "has_intersections": False,
    "intersection_y_coords": [],
    "xml_commands": []
}

# Find file (expected path or recent)
found_file = None
if os.path.exists(EXPECTED_PATH):
    found_file = EXPECTED_PATH
else:
    # Check for any recent .ggb file in documents
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
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME

    # Analyze XML content
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # 1. Check for Slider (numeric element)
                # Look for <element type="numeric" label="offset"> ... <slider ... />
                # or just any slider
                sliders = re.findall(r'<element type="numeric"[^>]*label="([^"]+)"', xml_content)
                has_slider_elem = '<slider' in xml_content
                result["has_slider"] = has_slider_elem
                if sliders and has_slider_elem:
                    result["slider_label"] = sliders[0]

                # 2. Check for Sequence command (optimization requirement)
                # <command name="Sequence">
                seq_cmds = re.findall(r'<command name="Sequence"', xml_content, re.IGNORECASE)
                result["has_sequence"] = len(seq_cmds) > 0
                result["sequence_count"] = len(seq_cmds)
                
                # Record all commands for debugging
                result["xml_commands"] = list(set(re.findall(r'<command name="([^"]+)"', xml_content)))

                # 3. Check for Intersections (y = 0, 80, 160...)
                # Look for lines or points with these Y coordinates
                # Or look for Sequence inputs that generate them
                y_coords_found = []
                targets = [80, 160, 240, 320]
                for t in targets:
                    # Check for explicit numbers in XML (definition of lines or points)
                    # This is a loose check; robust check requires full XML parsing, but grep is faster
                    if f'"{t}"' in xml_content or f'"{t}.0"' in xml_content:
                        y_coords_found.append(t)
                
                result["intersection_y_coords"] = y_coords_found
                result["has_intersections"] = len(y_coords_found) >= 3

                # 4. Check for Car Trajectory (Slope ~11.2)
                # Look for line with equation involving 11.2x
                # GeoGebra stores lines often as coords attributes or command inputs
                # Check for "11.2" or "25 mph" converted values
                if "11.2" in xml_content or "11,2" in xml_content:
                    result["has_car_trajectory"] = True
                    result["car_slope"] = 11.2
                elif "25" in xml_content: # Maybe they used mph directly without conversion?
                     # Weak signal, but noted
                     pass

    except Exception as e:
        result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="