#!/bin/bash
# Export script for Hurricane Katrina Track Analysis task
set -o pipefail

# Ensure fallback result on any failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "points_found": 0,
    "polyline_found": false,
    "distance_value_found": false,
    "annotation_found": false,
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

echo "=== Exporting Katrina Analysis Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python for analysis to be robust against XML structure
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time, math

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/katrina_analysis.ggb"
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
    "points_found": 0,
    "correct_points": 0,
    "polyline_found": False,
    "distance_value_found": False,
    "extracted_distance": None,
    "annotation_found": False,
    "spreadsheet_used": False,
    "xml_commands": []
}

# 1. Find the file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Fallback search
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

    # 2. Analyze XML
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Check for Spreadsheet usage (cell tags)
                if '<element type="numeric" label="A1">' in xml_content or '<spreadsheetView' in xml_content:
                    result["spreadsheet_used"] = True

                # Count Points
                # We want to check for points that match our data
                # Expected: (-75.1, 23.1), (-76.5, 24.5), etc.
                # XML points: <coords x="-75.1" y="23.1" z="1"/>
                
                point_matches = re.findall(r'<coords x="([^"]+)" y="([^"]+)" z="1"', xml_content)
                result["points_found"] = len(point_matches)
                
                expected_data = [
                    (-75.1, 23.1), (-76.5, 24.5), (-79.0, 26.0), (-81.3, 25.4),
                    (-83.3, 24.6), (-88.1, 25.9), (-89.6, 28.2), (-89.1, 32.6)
                ]
                
                correct_count = 0
                for px_str, py_str in point_matches:
                    try:
                        px = float(px_str)
                        py = float(py_str)
                        # Check if this point matches any expected point within tolerance
                        for ex, ey in expected_data:
                            if abs(px - ex) < 0.2 and abs(py - ey) < 0.2:
                                correct_count += 1
                                break
                    except ValueError:
                        pass
                result["correct_points"] = correct_count

                # Check for Polyline
                # <command name="Polyline"> or element type="polyline"
                if re.search(r'<command name="Polyline"', xml_content, re.IGNORECASE) or \
                   re.search(r'<element type="polyline"', xml_content, re.IGNORECASE):
                    result["polyline_found"] = True

                # Check for Distance Calculation
                # We look for a numeric value around 22-26 (degrees) OR 2000-3000 (km)
                # Text elements might contain "2500 km"
                
                # Extract text labels
                text_elements = re.findall(r'<element type="text".*?>(.*?)</element>', xml_content, re.DOTALL)
                full_text = " ".join(text_elements) + " " + xml_content
                
                # Look for numbers in valid range for KM
                numbers = re.findall(r'(\d{4})', full_text) # 4 digit numbers
                for num_str in numbers:
                    val = float(num_str)
                    if 2000 <= val <= 3000:
                        result["distance_value_found"] = True
                        result["extracted_distance"] = val
                        break
                
                # Check for keywords
                if "km" in full_text.lower() or "kilometers" in full_text.lower():
                    result["annotation_found"] = True

    except Exception as e:
        result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="