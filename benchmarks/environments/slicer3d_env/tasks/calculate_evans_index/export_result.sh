#!/bin/bash
echo "=== Exporting Evans Index Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/evans_result.json"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any Slicer manipulation)
echo "Capturing final screenshot..."
FINAL_SCREENSHOT="$SCREENSHOT_DIR/evans_final.png"
take_screenshot "$FINAL_SCREENSHOT" ga
sleep 1

# Also capture to tmp for verification
take_screenshot /tmp/task_final_state.png ga

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
fi

# Create export script for Slicer to run
EXPORT_SCRIPT="/tmp/export_evans_measurements.py"
cat > "$EXPORT_SCRIPT" << 'PYEXPORT'
import slicer
import json
import os
import math

export_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(export_dir, exist_ok=True)

result = {
    "measurements_found": False,
    "line_count": 0,
    "lines": [],
    "evans_index": None,
    "same_level": False,
    "z_difference_mm": None,
    "volume_loaded": False,
    "frontal_horn_width_mm": None,
    "skull_width_mm": None,
    "interpretation": None
}

try:
    # Check for loaded volumes
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    result["volume_loaded"] = len(volume_nodes) > 0
    result["volume_count"] = len(volume_nodes)
    
    # Find all line markups (rulers/lines)
    markup_line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
    result["line_count"] = len(markup_line_nodes)
    
    print(f"Found {len(markup_line_nodes)} line markup node(s)")
    
    if len(markup_line_nodes) >= 1:
        result["measurements_found"] = True
        
        for i, node in enumerate(markup_line_nodes):
            n_points = node.GetNumberOfControlPoints()
            print(f"  Line {i}: '{node.GetName()}' with {n_points} control points")
            
            if n_points >= 2:
                # Get endpoints
                p1 = [0.0, 0.0, 0.0]
                p2 = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(0, p1)
                node.GetNthControlPointPosition(1, p2)
                
                # Calculate length (3D distance)
                length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
                
                # Calculate angle from horizontal in axial plane (X-Y)
                dx = p2[0] - p1[0]
                dy = p2[1] - p1[1]
                
                if abs(dx) > 0.001:
                    angle_rad = math.atan2(abs(dy), abs(dx))
                    angle_deg = math.degrees(angle_rad)
                else:
                    angle_deg = 90.0
                
                # Z-coordinate (average of endpoints)
                z_coord = (p1[2] + p2[2]) / 2.0
                
                line_data = {
                    "name": node.GetName(),
                    "p1": list(p1),
                    "p2": list(p2),
                    "length_mm": round(length, 2),
                    "z_coordinate": round(z_coord, 2),
                    "angle_from_horizontal_deg": round(angle_deg, 2),
                    "is_horizontal": angle_deg < 15.0
                }
                result["lines"].append(line_data)
                
                print(f"    Length: {length:.2f} mm, Z: {z_coord:.2f}, Angle: {angle_deg:.1f}°")
        
        # If we have at least 2 lines, calculate Evans Index
        if len(result["lines"]) >= 2:
            # Sort by length - smaller is frontal horn, larger is skull
            sorted_lines = sorted(result["lines"], key=lambda x: x["length_mm"])
            
            frontal_horn = sorted_lines[0]
            skull_width = sorted_lines[-1]
            
            result["frontal_horn_width_mm"] = frontal_horn["length_mm"]
            result["skull_width_mm"] = skull_width["length_mm"]
            
            # Check if at same Z level
            z_diff = abs(frontal_horn["z_coordinate"] - skull_width["z_coordinate"])
            result["z_difference_mm"] = round(z_diff, 2)
            result["same_level"] = z_diff < 5.0
            
            # Calculate Evans Index
            if skull_width["length_mm"] > 0:
                evans = frontal_horn["length_mm"] / skull_width["length_mm"]
                result["evans_index"] = round(evans, 4)
                
                # Clinical interpretation
                if evans < 0.30:
                    result["interpretation"] = "Normal (no ventriculomegaly)"
                elif evans < 0.35:
                    result["interpretation"] = "Borderline ventriculomegaly"
                else:
                    result["interpretation"] = "Ventriculomegaly (suggests hydrocephalus)"
                
                print(f"\nEvans Index: {evans:.4f}")
                print(f"Interpretation: {result['interpretation']}")
        
        # Try to save markup nodes
        for node in markup_line_nodes:
            name = node.GetName().lower()
            try:
                if "frontal" in name or "horn" in name or "ventri" in name:
                    save_path = os.path.join(export_dir, "frontal_horn.mrk.json")
                    slicer.util.saveNode(node, save_path)
                    print(f"Saved frontal horn markup to {save_path}")
                elif "skull" in name or "thorac" in name or "width" in name:
                    save_path = os.path.join(export_dir, "skull_width.mrk.json")
                    slicer.util.saveNode(node, save_path)
                    print(f"Saved skull width markup to {save_path}")
            except Exception as e:
                print(f"Could not save markup: {e}")
    
    # Also save all markups combined
    try:
        mrk_path = os.path.join(export_dir, "evans_measurements.mrk.json")
        if markup_line_nodes:
            # Save scene as JSON
            all_data = {
                "markups": result["lines"],
                "evans_index": result["evans_index"],
                "interpretation": result["interpretation"]
            }
            with open(mrk_path, "w") as f:
                json.dump(all_data, f, indent=2)
            print(f"Saved combined measurements to {mrk_path}")
    except Exception as e:
        print(f"Could not save combined markup: {e}")

except Exception as e:
    result["error"] = str(e)
    print(f"ERROR in export: {e}")
    import traceback
    traceback.print_exc()

# Save result JSON
output_path = os.path.join(export_dir, "evans_export_result.json")
try:
    with open(output_path, "w") as f:
        json.dump(result, f, indent=2)
    print(f"\nExport result saved to {output_path}")
except Exception as e:
    print(f"Could not save result: {e}")

# Also save to /tmp for easy access
try:
    with open("/tmp/evans_measurements.json", "w") as f:
        json.dump(result, f, indent=2)
except:
    pass

print("\n" + "=" * 50)
print(json.dumps(result, indent=2))
print("=" * 50)
PYEXPORT

chmod 644 "$EXPORT_SCRIPT"

# Run export script in Slicer
MEASUREMENTS_DATA=""
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Exporting measurements from Slicer..."
    
    # Method 1: Run via Slicer CLI with timeout
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window \
        --python-script "$EXPORT_SCRIPT" > /tmp/slicer_export.log 2>&1 || true
    
    sleep 3
    
    # Check if export succeeded
    if [ -f "/tmp/evans_measurements.json" ]; then
        echo "Measurements exported successfully"
        MEASUREMENTS_DATA=$(cat /tmp/evans_measurements.json)
    elif [ -f "$EXPORT_DIR/evans_export_result.json" ]; then
        echo "Found export in output directory"
        cp "$EXPORT_DIR/evans_export_result.json" /tmp/evans_measurements.json
        MEASUREMENTS_DATA=$(cat /tmp/evans_measurements.json)
    fi
fi

# Parse measurements from exported data
LINE_COUNT=0
EVANS_INDEX=""
FRONTAL_HORN_MM=""
SKULL_WIDTH_MM=""
SAME_LEVEL="false"
Z_DIFFERENCE=""
INTERPRETATION=""
VOLUME_LOADED="false"

if [ -f "/tmp/evans_measurements.json" ]; then
    LINE_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/evans_measurements.json')); print(d.get('line_count', 0))" 2>/dev/null || echo "0")
    EVANS_INDEX=$(python3 -c "import json; d=json.load(open('/tmp/evans_measurements.json')); print(d.get('evans_index', '') or '')" 2>/dev/null || echo "")
    FRONTAL_HORN_MM=$(python3 -c "import json; d=json.load(open('/tmp/evans_measurements.json')); print(d.get('frontal_horn_width_mm', '') or '')" 2>/dev/null || echo "")
    SKULL_WIDTH_MM=$(python3 -c "import json; d=json.load(open('/tmp/evans_measurements.json')); print(d.get('skull_width_mm', '') or '')" 2>/dev/null || echo "")
    SAME_LEVEL=$(python3 -c "import json; d=json.load(open('/tmp/evans_measurements.json')); print('true' if d.get('same_level') else 'false')" 2>/dev/null || echo "false")
    Z_DIFFERENCE=$(python3 -c "import json; d=json.load(open('/tmp/evans_measurements.json')); print(d.get('z_difference_mm', '') or '')" 2>/dev/null || echo "")
    INTERPRETATION=$(python3 -c "import json; d=json.load(open('/tmp/evans_measurements.json')); print(d.get('interpretation', '') or '')" 2>/dev/null || echo "")
    VOLUME_LOADED=$(python3 -c "import json; d=json.load(open('/tmp/evans_measurements.json')); print('true' if d.get('volume_loaded') else 'false')" 2>/dev/null || echo "false")
fi

echo "Extracted measurements:"
echo "  Line count: $LINE_COUNT"
echo "  Evans Index: $EVANS_INDEX"
echo "  Frontal horn: $FRONTAL_HORN_MM mm"
echo "  Skull width: $SKULL_WIDTH_MM mm"
echo "  Same level: $SAME_LEVEL (Z diff: $Z_DIFFERENCE mm)"
echo "  Interpretation: $INTERPRETATION"

# Check for screenshots
SCREENSHOT_EXISTS="false"
SCREENSHOT_FILE=""
SCREENSHOT_SIZE_KB=0

for f in "$FINAL_SCREENSHOT" "$SCREENSHOT_DIR"/evans*.png /tmp/task_final_state.png; do
    if [ -f "$f" ]; then
        fsize=$(stat -c%s "$f" 2>/dev/null || echo "0")
        if [ "$fsize" -gt 10000 ]; then
            SCREENSHOT_EXISTS="true"
            SCREENSHOT_FILE="$f"
            SCREENSHOT_SIZE_KB=$((fsize / 1024))
            break
        fi
    fi
done

# Check if measurements file was exported
MEASUREMENTS_EXPORTED="false"
MEASUREMENTS_FILE=""
for f in "$EXPORT_DIR/evans_measurements.mrk.json" "$EXPORT_DIR/evans_export_result.json" /tmp/evans_measurements.json; do
    if [ -f "$f" ]; then
        MEASUREMENTS_EXPORTED="true"
        MEASUREMENTS_FILE="$f"
        break
    fi
done

# Build final result JSON
TEMP_JSON=$(mktemp /tmp/evans_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "volume_loaded": $VOLUME_LOADED,
    "line_count": $LINE_COUNT,
    "measurements_found": $([ "$LINE_COUNT" -ge 1 ] && echo "true" || echo "false"),
    "two_lines_exist": $([ "$LINE_COUNT" -ge 2 ] && echo "true" || echo "false"),
    "same_level": $SAME_LEVEL,
    "z_difference_mm": ${Z_DIFFERENCE:-null},
    "frontal_horn_width_mm": ${FRONTAL_HORN_MM:-null},
    "skull_width_mm": ${SKULL_WIDTH_MM:-null},
    "evans_index": ${EVANS_INDEX:-null},
    "interpretation": "${INTERPRETATION}",
    "measurements_exported": $MEASUREMENTS_EXPORTED,
    "measurements_file": "${MEASUREMENTS_FILE}",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_file": "${SCREENSHOT_FILE}",
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START))
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"