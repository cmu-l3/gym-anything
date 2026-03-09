#!/bin/bash
# Export script for Conic Eccentricity Explorer task
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

echo "=== Exporting Conic Eccentricity Explorer Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python to inspect the GGB file structure
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/conic_eccentricity.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_created_during_task": False,
    "has_eccentricity_slider": False,
    "slider_range_ok": False,
    "has_curve_command": False,
    "curve_uses_trig": False,
    "curve_uses_slider": False,
    "has_focus_point": False,
    "has_text_annotation": False,
    "latus_rectum_defined": False,
    "slider_details": {},
    "xml_commands": []
}

# 1. Find file
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Check for recent .ggb files
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
    mtime = os.path.getmtime(found_file)
    result["file_created_during_task"] = int(mtime) > TASK_START_TIME

    # 2. Parse XML
    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Check slider 'e'
                # Look for numeric element with label 'e' and slider tag
                # <element type="numeric" label="e"> ... <slider min="..." max="..." ... />
                try:
                    root = ET.fromstring(xml_content)
                    
                    # Check Elements
                    for elem in root.iter('element'):
                        etype = elem.get('type', '')
                        label = elem.get('label', '')
                        
                        # Slider check
                        if etype == 'numeric':
                            slider = elem.find('slider')
                            if slider is not None:
                                s_min = float(slider.get('min', 0))
                                s_max = float(slider.get('max', 0))
                                
                                # Check if this is likely the eccentricity slider
                                if label == 'e' or 'ecc' in label.lower() or (s_min <= 0.1 and s_max >= 1.5):
                                    result["has_eccentricity_slider"] = True
                                    result["slider_details"] = {"label": label, "min": s_min, "max": s_max}
                                    if s_min <= 0 and s_max >= 1.5:
                                        result["slider_range_ok"] = True
                                        
                            # Check for Latus Rectum definition (val ~ 2)
                            val_elem = elem.find('value')
                            if val_elem is not None:
                                val = float(val_elem.get('val', 0))
                                if abs(val - 2.0) < 0.1:
                                    result["latus_rectum_defined"] = True

                        # Check Focus Point (0,0)
                        if etype == 'point':
                            coords = elem.find('coords')
                            if coords is not None:
                                x = float(coords.get('x', 0))
                                y = float(coords.get('y', 0))
                                z = float(coords.get('z', 1))
                                if z != 0:
                                    x, y = x/z, y/z
                                if abs(x) < 0.1 and abs(y) < 0.1:
                                    result["has_focus_point"] = True

                        # Check Text
                        if etype == 'text':
                            result["has_text_annotation"] = True

                    # Check Commands (Curve)
                    for cmd in root.iter('command'):
                        name = cmd.get('name', '')
                        result["xml_commands"].append(name)
                        
                        if name == 'Curve':
                            result["has_curve_command"] = True
                            # Check input arguments for trig and slider usage
                            inp = cmd.find('input')
                            if inp is not None:
                                args = str(inp.attrib)
                                # Basic string check for logic
                                cmd_string = ET.tostring(cmd, encoding='unicode').lower()
                                if 'cos' in cmd_string or 'sin' in cmd_string:
                                    result["curve_uses_trig"] = True
                                if 'e' in cmd_string or result.get("slider_details", {}).get("label", "___") in cmd_string:
                                    result["curve_uses_slider"] = True

                except ET.ParseError:
                    # Fallback regex if XML parsing fails
                    if re.search(r'<command name="Curve"', xml_content):
                        result["has_curve_command"] = True
                    if re.search(r'<element type="numeric" label="e"', xml_content):
                        result["has_eccentricity_slider"] = True

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"