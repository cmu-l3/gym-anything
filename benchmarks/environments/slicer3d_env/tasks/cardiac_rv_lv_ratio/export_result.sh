#!/bin/bash
echo "=== Exporting Cardiac RV/LV Ratio Result ==="

source /workspace/scripts/task_utils.sh

CARDIAC_DIR="/home/ga/Documents/SlicerData/Cardiac"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_RV="$CARDIAC_DIR/rv_measurement.mrk.json"
OUTPUT_LV="$CARDIAC_DIR/lv_measurement.mrk.json"
OUTPUT_REPORT="$CARDIAC_DIR/cardiac_report.json"

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/cardiac_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from Slicer
    cat > /tmp/export_cardiac_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Cardiac"
os.makedirs(output_dir, exist_ok=True)

print("Exporting cardiac measurements from Slicer...")

# Find all line markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

for node in line_nodes:
    node_name = node.GetName().lower()
    n_points = node.GetNumberOfControlPoints()
    
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        print(f"  {node.GetName()}: {length:.2f} mm")
        
        # Try to match to RV or LV
        if 'rv' in node_name or 'right' in node_name:
            out_path = os.path.join(output_dir, "rv_measurement.mrk.json")
        elif 'lv' in node_name or 'left' in node_name:
            out_path = os.path.join(output_dir, "lv_measurement.mrk.json")
        else:
            out_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        
        # Save using Slicer's native format
        slicer.util.saveNode(node, out_path)
        print(f"    Saved to: {out_path}")

# Also check for ruler annotations or other measurement types
ruler_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsROINode")
print(f"Found {len(ruler_nodes)} ROI node(s)")

print("Export complete")
PYEOF

    # Run export script
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_cardiac_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 5
fi

# Check for RV measurement file
RV_EXISTS="false"
RV_PATH=""
RV_DIAMETER=""
RV_MTIME="0"

POSSIBLE_RV_PATHS=(
    "$OUTPUT_RV"
    "$CARDIAC_DIR/RV.mrk.json"
    "$CARDIAC_DIR/rv.mrk.json"
    "$CARDIAC_DIR/right_ventricle.mrk.json"
)

for path in "${POSSIBLE_RV_PATHS[@]}"; do
    if [ -f "$path" ]; then
        RV_EXISTS="true"
        RV_PATH="$path"
        RV_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Extract length from markup file
        RV_DIAMETER=$(python3 -c "
import json
import math
try:
    with open('$path') as f:
        data = json.load(f)
    # Try Slicer markup format
    if 'markups' in data and len(data['markups']) > 0:
        markup = data['markups'][0]
        if 'controlPoints' in markup and len(markup['controlPoints']) >= 2:
            p1 = markup['controlPoints'][0]['position']
            p2 = markup['controlPoints'][1]['position']
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            print(f'{length:.2f}')
        elif 'measurements' in markup:
            for m in markup['measurements']:
                if m.get('name') == 'length' or 'length' in m.get('name', '').lower():
                    print(f\"{m['value']:.2f}\")
                    break
except Exception as e:
    pass
" 2>/dev/null || echo "")
        
        if [ -n "$RV_DIAMETER" ]; then
            echo "Found RV measurement: $RV_DIAMETER mm at $path"
            if [ "$path" != "$OUTPUT_RV" ]; then
                cp "$path" "$OUTPUT_RV" 2>/dev/null || true
            fi
            break
        fi
    fi
done

# Check for LV measurement file
LV_EXISTS="false"
LV_PATH=""
LV_DIAMETER=""
LV_MTIME="0"

POSSIBLE_LV_PATHS=(
    "$OUTPUT_LV"
    "$CARDIAC_DIR/LV.mrk.json"
    "$CARDIAC_DIR/lv.mrk.json"
    "$CARDIAC_DIR/left_ventricle.mrk.json"
)

for path in "${POSSIBLE_LV_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LV_EXISTS="true"
        LV_PATH="$path"
        LV_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        LV_DIAMETER=$(python3 -c "
import json
import math
try:
    with open('$path') as f:
        data = json.load(f)
    if 'markups' in data and len(data['markups']) > 0:
        markup = data['markups'][0]
        if 'controlPoints' in markup and len(markup['controlPoints']) >= 2:
            p1 = markup['controlPoints'][0]['position']
            p2 = markup['controlPoints'][1]['position']
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            print(f'{length:.2f}')
        elif 'measurements' in markup:
            for m in markup['measurements']:
                if m.get('name') == 'length' or 'length' in m.get('name', '').lower():
                    print(f\"{m['value']:.2f}\")
                    break
except Exception as e:
    pass
" 2>/dev/null || echo "")
        
        if [ -n "$LV_DIAMETER" ]; then
            echo "Found LV measurement: $LV_DIAMETER mm at $path"
            if [ "$path" != "$OUTPUT_LV" ]; then
                cp "$path" "$OUTPUT_LV" 2>/dev/null || true
            fi
            break
        fi
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_RV=""
REPORTED_LV=""
REPORTED_RATIO=""
REPORTED_CLASS=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$CARDIAC_DIR/report.json"
    "$CARDIAC_DIR/cardiac.json"
    "/home/ga/Documents/cardiac_report.json"
    "/home/ga/cardiac_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_RV=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('rv_diameter_mm', d.get('rv_diameter', d.get('rv', '')))
    if v: print(f'{float(v):.2f}')
except: pass
" 2>/dev/null || echo "")

        REPORTED_LV=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('lv_diameter_mm', d.get('lv_diameter', d.get('lv', '')))
    if v: print(f'{float(v):.2f}')
except: pass
" 2>/dev/null || echo "")

        REPORTED_RATIO=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('rv_lv_ratio', d.get('ratio', ''))
    if v: print(f'{float(v):.3f}')
except: pass
" 2>/dev/null || echo "")

        REPORTED_CLASS=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    print(d.get('classification', d.get('finding', d.get('assessment', ''))))
except: pass
" 2>/dev/null || echo "")
        
        echo "  RV: $REPORTED_RV, LV: $REPORTED_LV, Ratio: $REPORTED_RATIO, Class: $REPORTED_CLASS"
        break
    fi
done

# Check if measurements were created during task (anti-gaming)
RV_CREATED_DURING_TASK="false"
LV_CREATED_DURING_TASK="false"

if [ "$RV_MTIME" != "0" ] && [ "$TASK_START" != "0" ]; then
    if [ "$RV_MTIME" -gt "$TASK_START" ]; then
        RV_CREATED_DURING_TASK="true"
    fi
fi

if [ "$LV_MTIME" != "0" ] && [ "$TASK_START" != "0" ]; then
    if [ "$LV_MTIME" -gt "$TASK_START" ]; then
        LV_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/cardiac_gt.json" /tmp/cardiac_gt.json 2>/dev/null || true
chmod 644 /tmp/cardiac_gt.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/cardiac_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "rv_measurement_exists": $RV_EXISTS,
    "rv_measurement_path": "$RV_PATH",
    "rv_diameter_mm": "$RV_DIAMETER",
    "rv_created_during_task": $RV_CREATED_DURING_TASK,
    "lv_measurement_exists": $LV_EXISTS,
    "lv_measurement_path": "$LV_PATH",
    "lv_diameter_mm": "$LV_DIAMETER",
    "lv_created_during_task": $LV_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_rv_mm": "$REPORTED_RV",
    "reported_lv_mm": "$REPORTED_LV",
    "reported_ratio": "$REPORTED_RATIO",
    "reported_classification": "$REPORTED_CLASS",
    "screenshot_exists": $([ -f "/tmp/cardiac_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/cardiac_task_result.json 2>/dev/null || sudo rm -f /tmp/cardiac_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cardiac_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/cardiac_task_result.json
chmod 666 /tmp/cardiac_task_result.json 2>/dev/null || sudo chmod 666 /tmp/cardiac_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/cardiac_task_result.json
echo ""
echo "=== Export Complete ==="