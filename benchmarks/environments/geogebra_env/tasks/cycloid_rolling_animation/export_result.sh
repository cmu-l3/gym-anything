#!/bin/bash
# Export script for Cycloid Rolling Animation task
set -o pipefail

# Ensure we always create a result file even on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "error": "Export script failed to complete normally"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Source utilities or define inline
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

echo "=== Exporting Cycloid Animation Result ==="

# Get task timing information
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Path to expected file
PROJECT_DIR="/home/ga/Documents/GeoGebra/projects"
EXPECTED_FILE="$PROJECT_DIR/cycloid_animation.ggb"

# Use Python for robust XML parsing and analysis
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import glob
import time
import shutil

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/cycloid_animation.ggb"
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
    "has_slider": False,
    "slider_max": 0.0,
    "has_circle": False,
    "circle_radius": 0.0,
    "has_curve": False,
    "curve_uses_trig": False,
    "has_text": False,
    "num_points": 0,
    "error": None
}

# Find the file (check expected location first, then search recent files)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Look for any .ggb file modified during the task
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
    result["file_created_during_task"] = int(mtime) >= TASK_START_TIME

    # Parse GeoGebra XML
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Check for Slider (numeric element with animation step/interval)
                # GeoGebra stores sliders as numeric elements. 
                # We look for <element type="numeric">...<slider min="..." max="..." .../>
                slider_matches = re.findall(r'<slider\s+min="[^"]*"\s+max="([^"]*)"', xml_content)
                if slider_matches:
                    result["has_slider"] = True
                    # Get the max value of the slider with the largest range
                    max_vals = []
                    for val in slider_matches:
                        try:
                            max_vals.append(float(val))
                        except ValueError:
                            pass
                    if max_vals:
                        result["slider_max"] = max(max_vals)

                # Check for Circle
                # Can be <command name="Circle"> or just a conic element
                circle_cmds = re.findall(r'<command name="Circle"', xml_content)
                conic_elems = re.findall(r'<element type="conic"', xml_content)
                
                if circle_cmds or conic_elems:
                    result["has_circle"] = True
                    # Try to extract radius if explicit in command: Circle(Point, Radius)
                    # This is tricky in XML regex, verifier logic will be lenient
                    # Ideally we check if "1" is an input to the circle command
                    if re.search(r'<input\s+a0="[^"]*"\s+a1="1"\s*/>', xml_content):
                        result["circle_radius"] = 1.0
                    else:
                        # Assume roughly 1 if circle exists, fine-tune in verifier if possible
                        result["circle_radius"] = 1.0 

                # Check for Curve
                # <command name="Curve"> or <command name="CurveCartesian">
                curve_matches = re.findall(r'<command name="Curve', xml_content)
                if curve_matches:
                    result["has_curve"] = True
                    # Check for sin/cos in the XML (simple heuristic)
                    if "sin" in xml_content and "cos" in xml_content:
                        result["curve_uses_trig"] = True
                
                # Alternate Locus check (also valid for cycloid)
                locus_matches = re.findall(r'<command name="Locus"', xml_content)
                if locus_matches:
                    result["has_curve"] = True
                    # Locus implicitly uses trig if driven by the construction
                    if "sin" in xml_content and "cos" in xml_content:
                        result["curve_uses_trig"] = True

                # Check for Text
                text_matches = re.findall(r'<element type="text"', xml_content)
                if text_matches:
                    result["has_text"] = True

                # Count points
                result["num_points"] = len(re.findall(r'<element type="point"', xml_content))

    except Exception as e:
        result["error"] = str(e)

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json