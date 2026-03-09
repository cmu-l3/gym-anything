#!/bin/bash
echo "=== Exporting Double Star Measurement Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/AstroImages/double_star"

python3 << 'PYEOF'
import json
import os
import glob
import re

PROJECT = "/home/ga/AstroImages/double_star"

result = {
    "results_file_found": False,
    "results_content": "",
    "reported_separation_arcsec": None,
    "reported_position_angle_deg": None,
    "reported_magnitude_diff": None,
    "measurement_files_found": False,
    "any_output": False,
}

# Search for results file in multiple locations
results_patterns = [
    f"{PROJECT}/double_star_results.txt",
    f"{PROJECT}/*results*",
    f"{PROJECT}/*report*",
    f"{PROJECT}/*measurement*",
    "/home/ga/Desktop/*double*",
    "/home/ga/*double*results*",
    "/home/ga/double_star_results.txt",
]

results_file = None
for pattern in results_patterns:
    matches = glob.glob(pattern)
    for m in matches:
        if os.path.isfile(m) and not m.endswith('.fits') and not m.endswith('.json'):
            results_file = m
            break
    if results_file:
        break

if results_file:
    result["results_file_found"] = True
    result["any_output"] = True
    try:
        with open(results_file, 'r') as f:
            content = f.read()
        result["results_content"] = content[:3000]

        # Parse separation (arcsec)
        sep_match = re.search(
            r'sep(?:aration)?[:\s=]+([0-9.]+)\s*(?:arcsec|"|\'\'|as)?',
            content, re.IGNORECASE
        )
        if sep_match:
            result["reported_separation_arcsec"] = float(sep_match.group(1))
        else:
            # Try generic number after "separation"
            sep_match = re.search(r'separation.*?([0-9]+\.?[0-9]*)', content, re.IGNORECASE)
            if sep_match:
                result["reported_separation_arcsec"] = float(sep_match.group(1))

        # Parse position angle
        pa_match = re.search(
            r'(?:position\s*angle|PA|pos\.?\s*angle)[:\s=]+([0-9.]+)\s*(?:deg|degrees|\u00b0)?',
            content, re.IGNORECASE
        )
        if pa_match:
            result["reported_position_angle_deg"] = float(pa_match.group(1))
        else:
            pa_match = re.search(r'angle.*?([0-9]+\.?[0-9]*)\s*(?:deg|\u00b0)', content, re.IGNORECASE)
            if pa_match:
                result["reported_position_angle_deg"] = float(pa_match.group(1))

        # Parse magnitude difference
        mag_match = re.search(
            r'(?:mag(?:nitude)?\s*diff(?:erence)?|delta\s*m|dm)[:\s=]+([0-9.]+)',
            content, re.IGNORECASE
        )
        if mag_match:
            result["reported_magnitude_diff"] = float(mag_match.group(1))
        else:
            mag_match = re.search(r'magnitude.*?([0-9]+\.[0-9]+)', content, re.IGNORECASE)
            if mag_match:
                result["reported_magnitude_diff"] = float(mag_match.group(1))

    except Exception as e:
        result["parse_error"] = str(e)

# Check for AstroImageJ measurement files (.xls, .csv, etc.)
meas_files = glob.glob(f"{PROJECT}/*Measurements*") + \
             glob.glob(f"{PROJECT}/*.xls") + \
             glob.glob(f"{PROJECT}/*.csv")
# Exclude files that are not measurement outputs
meas_files = [f for f in meas_files if 'catalog' not in f.lower() and 'target' not in f.lower()]
if meas_files:
    result["measurement_files_found"] = True
    result["any_output"] = True

os.system("pkill -f 'astroimagej\\|aij\\|AstroImageJ' 2>/dev/null")

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Export complete")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
