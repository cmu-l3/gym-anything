#!/bin/bash
echo "=== Exporting Hepatic Vein Confluence Mapping Result ==="

source /workspace/scripts/task_utils.sh

# Get patient number
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
else
    PATIENT_NUM="5"
fi

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

OUTPUT_MARKUP="$IRCADB_DIR/hepatic_vein_markups.mrk.json"
OUTPUT_SCREENSHOT="$SCREENSHOT_DIR/hepatic_confluence.png"
OUTPUT_REPORT="$IRCADB_DIR/hepatic_vein_report.json"

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/hepatic_vein_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export any markups from Slicer
    cat > /tmp/export_hepatic_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/IRCADb"
os.makedirs(output_dir, exist_ok=True)

all_markups = []
vein_markers = {"RHV": None, "MHV": None, "LHV": None}

# Check for fiducial markups
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    node_name = node.GetName().upper()
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i).upper()
        
        markup = {
            "node_name": node.GetName(),
            "label": label,
            "position_ras": pos
        }
        all_markups.append(markup)
        
        # Check if this is a hepatic vein marker
        for vein in ["RHV", "MHV", "LHV"]:
            if vein in label or vein in node_name:
                vein_markers[vein] = pos
                break
        
        # Also check for full names
        if "RIGHT" in label and "HEPATIC" in label:
            vein_markers["RHV"] = pos
        elif "MIDDLE" in label and "HEPATIC" in label:
            vein_markers["MHV"] = pos
        elif "LEFT" in label and "HEPATIC" in label:
            vein_markers["LHV"] = pos

# Check for line markups (for distance measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
distances = []

for node in line_nodes:
    if node.GetNumberOfControlPoints() >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        distances.append({
            "name": node.GetName(),
            "length_mm": length,
            "p1": p1,
            "p2": p2
        })

# Save all markups
output = {
    "all_markups": all_markups,
    "vein_markers": vein_markers,
    "distance_measurements": distances,
    "fiducial_count": len(all_markups),
    "line_count": len(distances)
}

meas_path = os.path.join(output_dir, "hepatic_vein_markups.mrk.json")
with open(meas_path, "w") as f:
    json.dump(output, f, indent=2)
print(f"Exported markups to {meas_path}")

# Save individual fiducial nodes
for node in fid_nodes:
    node_path = os.path.join(output_dir, f"{node.GetName()}_fiducials.mrk.json")
    slicer.util.saveNode(node, node_path)

print("Export complete")
PYEOF

    # Run export in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_hepatic_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_hepatic_markups" 2>/dev/null || true
fi

# Check for markup file
MARKUP_EXISTS="false"
MARKUP_PATH=""
FIDUCIAL_COUNT=0
VEINS_IDENTIFIED=0

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MARKUP"
    "$IRCADB_DIR/hepatic_vein_markups.mrk.json"
    "$IRCADB_DIR/markups.mrk.json"
    "/home/ga/Documents/hepatic_vein_markups.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_EXISTS="true"
        MARKUP_PATH="$path"
        echo "Found markup at: $path"
        
        # Extract fiducial count and vein info
        FIDUCIAL_COUNT=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('fiducial_count', len(data.get('all_markups', []))))
" 2>/dev/null || echo "0")
        
        VEINS_IDENTIFIED=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
vein_markers = data.get('vein_markers', {})
count = sum(1 for v in vein_markers.values() if v is not None)
print(count)
" 2>/dev/null || echo "0")
        
        if [ "$path" != "$OUTPUT_MARKUP" ]; then
            cp "$path" "$OUTPUT_MARKUP" 2>/dev/null || true
        fi
        break
    fi
done

# Check for screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_PATH=""
SCREENSHOT_MTIME="0"

POSSIBLE_SS_PATHS=(
    "$OUTPUT_SCREENSHOT"
    "$SCREENSHOT_DIR/hepatic_confluence.png"
    "$SCREENSHOT_DIR/screenshot.png"
    "$IRCADB_DIR/hepatic_confluence.png"
)

for path in "${POSSIBLE_SS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_PATH="$path"
        SCREENSHOT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found screenshot at: $path"
        if [ "$path" != "$OUTPUT_SCREENSHOT" ]; then
            cp "$path" "$OUTPUT_SCREENSHOT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if screenshot was created during task
SCREENSHOT_DURING_TASK="false"
if [ "$SCREENSHOT_EXISTS" = "true" ] && [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
    SCREENSHOT_DURING_TASK="true"
fi

# Check for report
REPORT_EXISTS="false"
REPORT_PATH=""
ANATOMICAL_PATTERN=""
RHV_MHV_DISTANCE=""
MHV_LHV_DISTANCE=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$IRCADB_DIR/hepatic_vein_report.json"
    "$IRCADB_DIR/report.json"
    "/home/ga/Documents/hepatic_vein_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Extract report fields
        ANATOMICAL_PATTERN=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('anatomical_pattern', ''))
" 2>/dev/null || echo "")
        
        RHV_MHV_DISTANCE=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('rhv_to_mhv_distance_mm', ''))
" 2>/dev/null || echo "")
        
        MHV_LHV_DISTANCE=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('mhv_to_lhv_distance_mm', ''))
" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json" /tmp/hepatic_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/hepatic_ground_truth.json 2>/dev/null || true

# Copy agent files for verification
if [ -f "$OUTPUT_MARKUP" ]; then
    cp "$OUTPUT_MARKUP" /tmp/agent_hepatic_markups.json 2>/dev/null || true
    chmod 644 /tmp/agent_hepatic_markups.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_hepatic_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_hepatic_report.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_SCREENSHOT" ]; then
    cp "$OUTPUT_SCREENSHOT" /tmp/agent_hepatic_screenshot.png 2>/dev/null || true
    chmod 644 /tmp/agent_hepatic_screenshot.png 2>/dev/null || true
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "patient_num": "$PATIENT_NUM",
    "markup_exists": $MARKUP_EXISTS,
    "markup_path": "$MARKUP_PATH",
    "fiducial_count": $FIDUCIAL_COUNT,
    "veins_identified": $VEINS_IDENTIFIED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "$SCREENSHOT_PATH",
    "screenshot_during_task": $SCREENSHOT_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "anatomical_pattern": "$ANATOMICAL_PATTERN",
    "rhv_mhv_distance_mm": "$RHV_MHV_DISTANCE",
    "mhv_lhv_distance_mm": "$MHV_LHV_DISTANCE",
    "final_screenshot": "/tmp/hepatic_vein_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/hepatic_vein_task_result.json 2>/dev/null || sudo rm -f /tmp/hepatic_vein_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/hepatic_vein_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/hepatic_vein_task_result.json
chmod 666 /tmp/hepatic_vein_task_result.json 2>/dev/null || sudo chmod 666 /tmp/hepatic_vein_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/hepatic_vein_task_result.json
echo ""
echo "=== Export Complete ==="