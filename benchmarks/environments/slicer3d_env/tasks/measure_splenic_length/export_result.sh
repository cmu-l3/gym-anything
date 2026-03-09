#!/bin/bash
echo "=== Exporting Splenic Length Measurement Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Get case ID
CASE_ID=$(cat /tmp/splenic_case_id.txt 2>/dev/null || echo "amos_0001")
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
MEASUREMENT_FILE="$EXPORTS_DIR/splenic_measurement.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
FINAL_SCREENSHOT="/tmp/splenic_final_screenshot.png"
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 1
DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    
    # Try to export any line measurements from Slicer
    echo "Attempting to export measurements from Slicer..."
    cat > /tmp/export_splenic_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)

# Look for line markups (ruler measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

measurements = []
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2]
        }
        measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm")

# Save all line measurements
if measurements:
    all_meas_path = os.path.join(output_dir, "slicer_line_measurements.json")
    with open(all_meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Exported {len(measurements)} line measurements")
    
    # If agent didn't create splenic_measurement.json, try to create it from the largest measurement
    splenic_path = os.path.join(output_dir, "splenic_measurement.json")
    if not os.path.exists(splenic_path) and measurements:
        # Use the longest measurement as the spleen measurement
        longest = max(measurements, key=lambda m: m['length_mm'])
        length_mm = longest['length_mm']
        
        # Classify
        if length_mm < 120:
            classification = "Normal"
            splenomegaly = False
        elif length_mm < 150:
            classification = "Mild splenomegaly"
            splenomegaly = True
        else:
            classification = "Marked splenomegaly"
            splenomegaly = True
        
        auto_result = {
            "length_mm": length_mm,
            "splenomegaly": splenomegaly,
            "assessment": classification,
            "note": "Auto-generated from Slicer line measurements"
        }
        with open(splenic_path, "w") as f:
            json.dump(auto_result, f, indent=2)
        print(f"Auto-generated splenic_measurement.json: {length_mm:.1f}mm = {classification}")
else:
    print("No line measurements found in scene")

print("Export complete")
PYEOF

    # Run export script with timeout
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_splenic_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 2
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_VALID="false"
MEASURED_LENGTH="0"
MEASURED_SPLENOMEGALY="null"
MEASURED_ASSESSMENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$MEASUREMENT_FILE" ]; then
    MEASUREMENT_EXISTS="true"
    
    # Check if file was created during task
    FILE_MTIME=$(stat -c %Y "$MEASUREMENT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Validate JSON structure
    MEASUREMENT_VALID=$(python3 << PYEOF
import json
try:
    with open("$MEASUREMENT_FILE", "r") as f:
        data = json.load(f)
    required = ["length_mm", "splenomegaly", "assessment"]
    if all(k in data for k in required):
        # Validate types
        if isinstance(data['length_mm'], (int, float)) and \
           isinstance(data['splenomegaly'], bool) and \
           isinstance(data['assessment'], str):
            print("true")
        else:
            print("false")
    else:
        print("false")
except Exception as e:
    print("false")
PYEOF
)
    
    if [ "$MEASUREMENT_VALID" = "true" ]; then
        MEASURED_LENGTH=$(python3 -c "import json; print(json.load(open('$MEASUREMENT_FILE'))['length_mm'])" 2>/dev/null || echo "0")
        MEASURED_SPLENOMEGALY=$(python3 -c "import json; print(str(json.load(open('$MEASUREMENT_FILE'))['splenomegaly']).lower())" 2>/dev/null || echo "null")
        MEASURED_ASSESSMENT=$(python3 -c "import json; print(json.load(open('$MEASUREMENT_FILE'))['assessment'])" 2>/dev/null || echo "")
    fi
fi

# Also check for Slicer-exported measurements
SLICER_MEASUREMENTS_FILE="$EXPORTS_DIR/slicer_line_measurements.json"
SLICER_MEASUREMENT_COUNT=0
SLICER_LONGEST_MM=0

if [ -f "$SLICER_MEASUREMENTS_FILE" ]; then
    SLICER_MEASUREMENT_COUNT=$(python3 -c "import json; print(len(json.load(open('$SLICER_MEASUREMENTS_FILE')).get('measurements', [])))" 2>/dev/null || echo "0")
    SLICER_LONGEST_MM=$(python3 -c "import json; meas=json.load(open('$SLICER_MEASUREMENTS_FILE')).get('measurements',[]); print(max([m['length_mm'] for m in meas]) if meas else 0)" 2>/dev/null || echo "0")
fi

# Load ground truth
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_spleen_gt.json"
GT_LENGTH="0"
GT_SPLENOMEGALY="null"
GT_CLASSIFICATION=""
GT_TOLERANCE="15"

if [ -f "$GT_FILE" ]; then
    GT_LENGTH=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['craniocaudal_length_mm'])" 2>/dev/null || echo "0")
    GT_SPLENOMEGALY=$(python3 -c "import json; print(str(json.load(open('$GT_FILE'))['expected_splenomegaly']).lower())" 2>/dev/null || echo "null")
    GT_CLASSIFICATION=$(python3 -c "import json; print(json.load(open('$GT_FILE'))['expected_classification'])" 2>/dev/null || echo "")
    GT_TOLERANCE=$(python3 -c "import json; print(json.load(open('$GT_FILE')).get('tolerance_percent', 15))" 2>/dev/null || echo "15")
fi

# Calculate measurement accuracy
MEASUREMENT_ACCURATE="false"
MEASUREMENT_ERROR_PERCENT="100"

if [ "$MEASUREMENT_VALID" = "true" ] && [ "$GT_LENGTH" != "0" ]; then
    ACCURACY_RESULT=$(python3 << PYEOF
measured = float("$MEASURED_LENGTH")
gt = float("$GT_LENGTH")
tolerance = float("$GT_TOLERANCE")

if gt > 0:
    error_pct = abs(measured - gt) / gt * 100
    accurate = error_pct <= tolerance
    print(f"{str(accurate).lower()},{error_pct:.1f}")
else:
    print("false,100")
PYEOF
)
    MEASUREMENT_ACCURATE=$(echo "$ACCURACY_RESULT" | cut -d',' -f1)
    MEASUREMENT_ERROR_PERCENT=$(echo "$ACCURACY_RESULT" | cut -d',' -f2)
fi

# Check classification accuracy
CLASSIFICATION_CORRECT="false"
if [ "$MEASURED_SPLENOMEGALY" = "$GT_SPLENOMEGALY" ]; then
    CLASSIFICATION_CORRECT="true"
fi

# Check for screenshots
SCREENSHOT_EXISTS="false"
LATEST_USER_SCREENSHOT=""
INITIAL_SCREENSHOT_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
FINAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
NEW_SCREENSHOTS=$((FINAL_SCREENSHOT_COUNT - INITIAL_SCREENSHOT_COUNT))

if [ "$NEW_SCREENSHOTS" -gt 0 ]; then
    LATEST_USER_SCREENSHOT=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$LATEST_USER_SCREENSHOT" ]; then
        SCREENSHOT_EXISTS="true"
        cp "$LATEST_USER_SCREENSHOT" /tmp/user_screenshot.png 2>/dev/null || true
    fi
fi

# Use final screenshot if no user screenshot
if [ "$SCREENSHOT_EXISTS" = "false" ] && [ -f "$FINAL_SCREENSHOT" ]; then
    LATEST_USER_SCREENSHOT="$FINAL_SCREENSHOT"
    SCREENSHOT_EXISTS="true"
fi

# Check measurement is in reasonable range
MEASUREMENT_REASONABLE="false"
if [ "$MEASUREMENT_VALID" = "true" ]; then
    MEASUREMENT_REASONABLE=$(python3 << PYEOF
measured = float("$MEASURED_LENGTH")
if 50 <= measured <= 300:
    print("true")
else:
    print("false")
PYEOF
)
fi

# Create result JSON
RESULT_FILE="/tmp/splenic_task_result.json"
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOFRESULT
{
    "case_id": "$CASE_ID",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measurement_valid": $MEASUREMENT_VALID,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "measured_length_mm": $MEASURED_LENGTH,
    "measured_splenomegaly": $MEASURED_SPLENOMEGALY,
    "measured_assessment": "$MEASURED_ASSESSMENT",
    "measurement_reasonable": $MEASUREMENT_REASONABLE,
    "ground_truth_length_mm": $GT_LENGTH,
    "ground_truth_splenomegaly": $GT_SPLENOMEGALY,
    "ground_truth_classification": "$GT_CLASSIFICATION",
    "measurement_error_percent": $MEASUREMENT_ERROR_PERCENT,
    "measurement_accurate": $MEASUREMENT_ACCURATE,
    "classification_correct": $CLASSIFICATION_CORRECT,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    "screenshot_path": "$LATEST_USER_SCREENSHOT",
    "final_screenshot": "$FINAL_SCREENSHOT",
    "slicer_measurement_count": $SLICER_MEASUREMENT_COUNT,
    "slicer_longest_mm": $SLICER_LONGEST_MM,
    "timestamp": "$(date -Iseconds)"
}
EOFRESULT

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
cat "$RESULT_FILE"