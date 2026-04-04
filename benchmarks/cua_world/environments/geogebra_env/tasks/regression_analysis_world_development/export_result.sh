#!/bin/bash
# Export script for Regression Analysis World Development task
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
    "num_points": 0,
    "num_lists": 0,
    "has_fitline": false,
    "has_fitlog": false,
    "has_scatter_data": false,
    "has_annotation": false,
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

echo "=== Exporting Regression Analysis World Development Result ==="

take_screenshot /tmp/task_end_screenshot.png

python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/world_regression.ggb"
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
    "num_points": 0,
    "num_lists": 0,
    "has_fitline": False,
    "has_fitlog": False,
    "has_scatter_data": False,
    "has_annotation": False,
    "xml_commands": [],
    "fitline_slope": None,
    "fitline_intercept": None
}

# Find the file
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
                result["num_points"] = len(re.findall(r'<element type="point"', xml_content, re.IGNORECASE))
                result["num_lists"] = len(re.findall(r'<element type="list"', xml_content, re.IGNORECASE))
                num_text = len(re.findall(r'<element type="text"', xml_content, re.IGNORECASE))

                # Extract commands
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))

                # Check for FitLine (linear regression)
                result["has_fitline"] = bool(re.search(r'<command name="FitLine"', xml_content, re.IGNORECASE))
                # Also check for FitPoly with degree 1 or just any Fit command
                if not result["has_fitline"]:
                    result["has_fitline"] = bool(re.search(r'<command name="Fit(Poly|LineX|)"', xml_content, re.IGNORECASE))

                # Check for FitLog (logarithmic regression)
                result["has_fitlog"] = bool(re.search(r'<command name="FitLog"', xml_content, re.IGNORECASE))
                # Also check for FitExp or FitPow as alternatives that show regression effort
                if not result["has_fitlog"]:
                    result["has_fitlog"] = bool(re.search(r'<command name="Fit(Exp|Pow|Growth|Sin|Logistic)"', xml_content, re.IGNORECASE))

                # Check for scatter plot / sufficient data points
                # Either individual points (≥10) or a list with multiple elements
                total_data_indicators = result["num_points"] + result["num_lists"]
                result["has_scatter_data"] = (result["num_points"] >= 10) or (result["num_lists"] >= 1)

                # Check for annotation
                result["has_annotation"] = num_text >= 1

                # Try to extract FitLine parameters from XML
                import xml.etree.ElementTree as ET
                try:
                    root = ET.fromstring(xml_content)
                    # Look for line elements that are regression lines
                    for elem in root.iter('element'):
                        if elem.get('type') == 'line':
                            coords = elem.find('coords')
                            if coords is not None:
                                try:
                                    la = float(coords.get('x', '0'))
                                    lb = float(coords.get('y', '0'))
                                    lc = float(coords.get('z', '0'))
                                    # For line ax + by + c = 0, slope = -a/b
                                    if abs(lb) > 0.001:
                                        slope = -la / lb
                                        intercept = -lc / lb
                                        # Check if slope is in realistic range for this data
                                        # Expected: positive slope, intercept around 60-75
                                        if 0 < slope < 1 and 50 < intercept < 85:
                                            result["fitline_slope"] = round(slope, 6)
                                            result["fitline_intercept"] = round(intercept, 4)
                                except (ValueError, ZeroDivisionError):
                                    pass
                except ET.ParseError:
                    pass

    except zipfile.BadZipFile as e:
        result["zip_error"] = str(e)
    except Exception as e:
        result["xml_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(f"  file_found: {result['file_found']}")
print(f"  file_created_during_task: {result['file_created_during_task']}")
print(f"  num_points: {result['num_points']}, num_lists: {result['num_lists']}")
print(f"  has_scatter_data: {result['has_scatter_data']}")
print(f"  has_fitline: {result['has_fitline']}")
print(f"  has_fitlog: {result['has_fitlog']}")
print(f"  has_annotation: {result['has_annotation']}")
print(f"  commands: {result.get('xml_commands', [])}")
PYEOF

echo "=== Export Complete ==="
