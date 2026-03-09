#!/bin/bash
echo "=== Exporting Duodenal Diameter Assessment Result ==="

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get the case ID used
CASE_ID="amos_duodenum_001"
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_MEASUREMENT="$AMOS_DIR/duodenal_measurement.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/duodenal_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_VALID="false"
MEASURED_DIAMETER="0"
MEASUREMENT_MTIME="0"

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/measurement.mrk.json"
    "$AMOS_DIR/ruler.mrk.json"
    "$AMOS_DIR/line.mrk.json"
    "/home/ga/Documents/duodenal_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found measurement at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Try to extract diameter from Slicer markup JSON
        MEASURED_DIAMETER=$(python3 << PYEOF
import json
import math
try:
    with open("$path", "r") as f:
        data = json.load(f)
    
    # Check for Slicer markup format
    if "markups" in data:
        for m in data["markups"]:
            # Check measurements array
            if "measurements" in m:
                for meas in m["measurements"]:
                    if "length" in meas.get("name", "").lower() or meas.get("name") == "length":
                        val = meas.get("value", 0)
                        if val > 0:
                            print(f"{val:.2f}")
                            exit(0)
            
            # Calculate from control points
            if "controlPoints" in m and len(m["controlPoints"]) >= 2:
                p1 = m["controlPoints"][0].get("position", [0, 0, 0])
                p2 = m["controlPoints"][1].get("position", [0, 0, 0])
                dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))
                if dist > 0:
                    print(f"{dist:.2f}")
                    exit(0)
    
    # Check for simple measurements array
    if "measurements" in data:
        for m in data["measurements"]:
            if m.get("type") == "line" and m.get("length_mm", 0) > 0:
                print(f"{m['length_mm']:.2f}")
                exit(0)
    
    print("0")
except Exception as e:
    print("0")
PYEOF
)
        if [ "$MEASURED_DIAMETER" != "0" ] && [ -n "$MEASURED_DIAMETER" ]; then
            MEASUREMENT_VALID="true"
        fi
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORTED_DIAMETER="0"
REPORTED_LOCATION=""
REPORTED_CLASSIFICATION=""
REPORT_MTIME="0"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/duodenum_report.json"
    "/home/ga/Documents/duodenal_report.json"
    "/home/ga/duodenal_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found report at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        eval $(python3 << PYEOF
import json
try:
    with open("$path", "r") as f:
        report = json.load(f)
    
    # Try various field names
    diameter = report.get("maximum_diameter_mm", 
               report.get("max_diameter_mm", 
               report.get("diameter_mm", 
               report.get("diameter", 0))))
    
    location = report.get("location", 
               report.get("segment", 
               report.get("duodenal_segment", "")))
    
    classification = report.get("classification", 
                     report.get("finding", 
                     report.get("assessment", "")))
    
    valid = "true" if diameter and diameter > 0 else "false"
    
    # Escape for shell
    location = str(location).replace('"', '\\"')
    classification = str(classification).replace('"', '\\"')
    
    print(f'REPORTED_DIAMETER="{diameter}"')
    print(f'REPORTED_LOCATION="{location}"')
    print(f'REPORTED_CLASSIFICATION="{classification}"')
    print(f'REPORT_VALID="{valid}"')
except Exception as e:
    print('REPORTED_DIAMETER="0"')
    print('REPORTED_LOCATION=""')
    print('REPORTED_CLASSIFICATION=""')
    print('REPORT_VALID="false"')
PYEOF
)
        break
    fi
done

# Check if files were created during task (anti-gaming)
MEASUREMENT_CREATED_DURING_TASK="false"
if [ "$MEASUREMENT_EXISTS" = "true" ] && [ "$MEASUREMENT_MTIME" -gt "$TASK_START" ]; then
    MEASUREMENT_CREATED_DURING_TASK="true"
fi

REPORT_CREATED_DURING_TASK="false"
if [ "$REPORT_EXISTS" = "true" ] && [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Copy ground truth for verifier
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_duodenum_gt.json" /tmp/duodenum_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/duodenum_ground_truth.json 2>/dev/null || true

# Check for screenshot
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "case_id": "$CASE_ID",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measurement_valid": $MEASUREMENT_VALID,
    "measurement_created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
    "measured_diameter_mm": $MEASURED_DIAMETER,
    "report_file_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_diameter_mm": $REPORTED_DIAMETER,
    "reported_location": "$REPORTED_LOCATION",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "measurement_file_path": "$OUTPUT_MEASUREMENT",
    "report_file_path": "$OUTPUT_REPORT",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/duodenal_task_result.json 2>/dev/null || sudo rm -f /tmp/duodenal_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/duodenal_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/duodenal_task_result.json
chmod 666 /tmp/duodenal_task_result.json 2>/dev/null || sudo chmod 666 /tmp/duodenal_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/duodenal_task_result.json
echo ""
echo "=== Export Complete ==="