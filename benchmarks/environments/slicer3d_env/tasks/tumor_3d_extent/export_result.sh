#!/bin/bash
echo "=== Exporting Three-Dimensional Tumor Extent Result ==="

source /workspace/scripts/task_utils.sh

# Get timing info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MARKUPS="$BRATS_DIR/tumor_dimensions.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/tumor_extent_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/tumor_extent_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export markups from Slicer scene before checking files
    echo "Exporting markups from Slicer..."
    cat > /tmp/export_tumor_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Get all line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        name = node.GetName()
        
        measurement = {
            "name": name,
            "type": "line",
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2],
        }
        all_measurements.append(measurement)
        print(f"  Ruler '{name}': {length:.2f} mm")
        
        # Save individual markup
        try:
            mrk_path = os.path.join(output_dir, f"{name}.mrk.json")
            slicer.util.saveNode(node, mrk_path)
        except:
            pass

# Save combined measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "tumor_dimensions.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "count": len(all_measurements)}, f, indent=2)
    print(f"\nExported {len(all_measurements)} measurements to {meas_path}")
else:
    print("WARNING: No ruler measurements found in scene")

print("Markup export complete")
PYEOF

    # Run export in background
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_tumor_markups.py --no-main-window > /tmp/slicer_export_markups.log 2>&1 &
    sleep 8
    pkill -f "export_tumor_markups" 2>/dev/null || true
fi

# Check for markups file
MARKUPS_EXISTS="false"
MARKUPS_CREATED_DURING_TASK="false"
MARKUPS_PATH=""

POSSIBLE_MARKUPS_PATHS=(
    "$OUTPUT_MARKUPS"
    "$BRATS_DIR/tumor_dimensions.mrk.json"
    "$BRATS_DIR/Tumor_AP_mm.mrk.json"
)

for path in "${POSSIBLE_MARKUPS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUPS_EXISTS="true"
        MARKUPS_PATH="$path"
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            MARKUPS_CREATED_DURING_TASK="true"
        fi
        echo "Found markups at: $path"
        if [ "$path" != "$OUTPUT_MARKUPS" ]; then
            cp "$path" "$OUTPUT_MARKUPS" 2>/dev/null || true
        fi
        break
    fi
done

# Extract measurements from markups
AP_MM=""
ML_MM=""
SI_MM=""
MARKUP_NAMES_FOUND=""

if [ -f "$OUTPUT_MARKUPS" ]; then
    # Extract each measurement by name
    MEAS_DATA=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/Documents/SlicerData/BraTS/tumor_dimensions.mrk.json") as f:
        data = json.load(f)
    
    measurements = data.get("measurements", [])
    result = {"ap": "", "ml": "", "si": "", "names": []}
    
    for m in measurements:
        name = m.get("name", "").lower()
        length = m.get("length_mm", 0)
        result["names"].append(m.get("name", ""))
        
        if "ap" in name or "anterior" in name:
            result["ap"] = str(length)
        elif "ml" in name or "mediolateral" in name or "lateral" in name:
            result["ml"] = str(length)
        elif "si" in name or "superior" in name or "inferior" in name:
            result["si"] = str(length)
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"ap": "", "ml": "", "si": "", "names": [], "error": str(e)}))
PYEOF
)
    
    AP_MM=$(echo "$MEAS_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ap',''))" 2>/dev/null || echo "")
    ML_MM=$(echo "$MEAS_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ml',''))" 2>/dev/null || echo "")
    SI_MM=$(echo "$MEAS_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('si',''))" 2>/dev/null || echo "")
    MARKUP_NAMES_FOUND=$(echo "$MEAS_DATA" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin).get('names',[])))" 2>/dev/null || echo "")
    
    echo "Measurements from markups: AP=$AP_MM, ML=$ML_MM, SI=$SI_MM"
fi

# Check for report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORTED_AP=""
REPORTED_ML=""
REPORTED_SI=""
REPORTED_VOLUME=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/tumor_extent_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/tumor_extent_report.json"
    "/home/ga/tumor_extent_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract values from report
        REPORTED_AP=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('AP_diameter_mm', d.get('ap_diameter_mm', d.get('AP', ''))))" 2>/dev/null || echo "")
        REPORTED_ML=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('ML_diameter_mm', d.get('ml_diameter_mm', d.get('ML', ''))))" 2>/dev/null || echo "")
        REPORTED_SI=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('SI_diameter_mm', d.get('si_diameter_mm', d.get('SI', ''))))" 2>/dev/null || echo "")
        REPORTED_VOLUME=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('ellipsoid_volume_ml', d.get('volume_ml', d.get('volume', ''))))" 2>/dev/null || echo "")
        
        echo "Report values: AP=$REPORTED_AP, ML=$REPORTED_ML, SI=$REPORTED_SI, Volume=$REPORTED_VOLUME"
        break
    fi
done

# Use report values if markup extraction failed
if [ -z "$AP_MM" ] && [ -n "$REPORTED_AP" ]; then
    AP_MM="$REPORTED_AP"
fi
if [ -z "$ML_MM" ] && [ -n "$REPORTED_ML" ]; then
    ML_MM="$REPORTED_ML"
fi
if [ -z "$SI_MM" ] && [ -n "$REPORTED_SI" ]; then
    SI_MM="$REPORTED_SI"
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_dimensions_gt.json" /tmp/dimensions_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/dimensions_ground_truth.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer
sleep 2

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "markups_exists": $MARKUPS_EXISTS,
    "markups_created_during_task": $MARKUPS_CREATED_DURING_TASK,
    "markups_path": "$MARKUPS_PATH",
    "markup_names_found": "$MARKUP_NAMES_FOUND",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "measurements": {
        "ap_mm": "$AP_MM",
        "ml_mm": "$ML_MM",
        "si_mm": "$SI_MM"
    },
    "reported_values": {
        "ap_mm": "$REPORTED_AP",
        "ml_mm": "$REPORTED_ML",
        "si_mm": "$REPORTED_SI",
        "volume_ml": "$REPORTED_VOLUME"
    },
    "sample_id": "$SAMPLE_ID",
    "screenshot_exists": $([ -f "/tmp/tumor_extent_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/dimensions_ground_truth.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/tumor_extent_result.json 2>/dev/null || sudo rm -f /tmp/tumor_extent_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tumor_extent_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tumor_extent_result.json
chmod 666 /tmp/tumor_extent_result.json 2>/dev/null || sudo chmod 666 /tmp/tumor_extent_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/tumor_extent_result.json
echo ""
echo "=== Export Complete ==="