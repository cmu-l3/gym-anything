#!/bin/bash
set -o pipefail

trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result..."
        cat > /tmp/task_result.json << EOF
{
    "file_found": false,
    "error": "Export script failed"
}
EOF
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting CO2 Analysis Result ==="

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Locate File and Metadata
PROJECT_FILE="/home/ga/Documents/GeoGebra/projects/co2_analysis.ggb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

FILE_FOUND="false"
FILE_CREATED_DURING="false"
FILE_SIZE=0

if [ -f "$PROJECT_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$PROJECT_FILE")
    FILE_MTIME=$(stat -c%Y "$PROJECT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
fi

# 3. Analyze GeoGebra XML content using Python
# We extract the GGB (zip) and parse the inner XML
python3 << PY_SCRIPT
import zipfile
import re
import json
import os
import xml.etree.ElementTree as ET

result = {
    "file_found": $FILE_FOUND, # Python bool
    "file_created_during_task": $FILE_CREATED_DURING,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "data_points_count": 0,
    "has_trend_model": False,
    "has_cycle_model": False,
    "has_prediction": False,
    "prediction_coords": {"x": 0, "y": 0},
    "commands_used": [],
    "xml_valid": False
}

ggb_path = "$PROJECT_FILE"

if os.path.exists(ggb_path):
    try:
        with zipfile.ZipFile(ggb_path, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8')
                result["xml_valid"] = True
                
                # 1. Check Data Points
                # Count <element type="point"> inside lists or free points
                # Heuristic: Real data import creates many points
                points = re.findall(r'<element type="point"', xml_content)
                result["data_points_count"] = len(points)
                
                # 2. Check Commands Used
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["commands_used"] = list(set(commands))
                
                # 3. Check Trend Model
                # Look for FitPoly, FitExp, or manual functions around y ~ 300-500
                if any(cmd in ["FitPoly", "FitExp", "FitGrowth"] for cmd in result["commands_used"]):
                    result["has_trend_model"] = True
                elif re.search(r'<element type="function"', xml_content):
                    # Fallback: check if a function exists that isn't the cycle
                    result["has_trend_model"] = True # We'll verify accuracy via prediction
                
                # 4. Check Cycle Model
                # Look for FitSin or explicit Sin() usage in function expression
                if "FitSin" in result["commands_used"]:
                    result["has_cycle_model"] = True
                elif re.search(r'sin\(', xml_content, re.IGNORECASE):
                    result["has_cycle_model"] = True
                    
                # 5. Check Prediction Point
                # Parse XML to find point named "Prediction"
                try:
                    root = ET.fromstring(xml_content)
                    construction = root.find("./construction")
                    if construction is not None:
                        for elem in construction.findall("element"):
                            label = elem.get("label", "")
                            if "prediction" in label.lower():
                                result["has_prediction"] = True
                                coords = elem.find("coords")
                                if coords is not None:
                                    x = float(coords.get("x", 0))
                                    y = float(coords.get("y", 0))
                                    z = float(coords.get("z", 1))
                                    if z != 0:
                                        result["prediction_coords"] = {"x": x/z, "y": y/z}
                except Exception as e:
                    print(f"XML Parsing error: {e}")

    except Exception as e:
        print(f"Zip analysis error: {e}")

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PY_SCRIPT

# 4. Final Permission Fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="