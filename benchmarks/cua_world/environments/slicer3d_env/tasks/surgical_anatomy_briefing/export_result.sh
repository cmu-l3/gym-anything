#!/bin/bash
echo "=== Exporting Surgical Anatomy Briefing Result ==="

source /workspace/scripts/task_utils.sh

# Get task parameters
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/anatomy_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export fiducials from Slicer before closing
    cat > /tmp/export_fiducials.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Find all fiducial nodes
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

all_fiducials = []

for node in fid_nodes:
    node_name = node.GetName()
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node_name}' has {n_points} control points")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        fiducial = {
            "node_name": node_name,
            "point_index": i,
            "label": label,
            "position_ras": pos
        }
        all_fiducials.append(fiducial)
        print(f"    Point {i}: label='{label}', pos={pos}")
    
    # Save individual node to markup JSON
    if n_points > 0:
        mrk_path = os.path.join(output_dir, f"{node_name}.mrk.json")
        try:
            slicer.util.saveNode(node, mrk_path)
            print(f"    Saved to {mrk_path}")
        except Exception as e:
            print(f"    Error saving: {e}")

# Save combined fiducials
if all_fiducials:
    combined_path = os.path.join(output_dir, "anatomical_landmarks.mrk.json")
    # Try to save from the first node that has fiducials
    for node in fid_nodes:
        if node.GetNumberOfControlPoints() > 0:
            try:
                slicer.util.saveNode(node, combined_path)
                print(f"Saved primary fiducial node to {combined_path}")
                break
            except Exception as e:
                print(f"Error: {e}")
    
    # Also save as plain JSON for easier parsing
    json_path = os.path.join(output_dir, "fiducials_export.json")
    with open(json_path, "w") as f:
        json.dump({"fiducials": all_fiducials}, f, indent=2)
    print(f"Exported {len(all_fiducials)} fiducials to {json_path}")
else:
    print("No fiducials found to export")

# Save scene if possible
scene_path = os.path.join(output_dir, "anatomy_scene.mrml")
try:
    slicer.util.saveScene(scene_path)
    print(f"Scene saved to {scene_path}")
except Exception as e:
    print(f"Could not save scene: {e}")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_fiducials.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_fiducials" 2>/dev/null || true
fi

# Check for fiducial files
FIDUCIALS_EXIST="false"
FIDUCIAL_COUNT=0
FIDUCIAL_PATH=""

POSSIBLE_FID_PATHS=(
    "$AMOS_DIR/anatomical_landmarks.mrk.json"
    "$AMOS_DIR/AnatomicalLandmarks.mrk.json"
    "$AMOS_DIR/fiducials.mrk.json"
    "$AMOS_DIR/landmarks.mrk.json"
)

for path in "${POSSIBLE_FID_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FIDUCIALS_EXIST="true"
        FIDUCIAL_PATH="$path"
        echo "Found fiducials at: $path"
        # Copy to expected location if needed
        if [ "$path" != "$AMOS_DIR/anatomical_landmarks.mrk.json" ]; then
            cp "$path" "$AMOS_DIR/anatomical_landmarks.mrk.json" 2>/dev/null || true
        fi
        break
    fi
done

# Parse fiducial data for verification
FIDUCIAL_LABELS=""
FIDUCIAL_POSITIONS=""

if [ -f "$AMOS_DIR/fiducials_export.json" ]; then
    FIDUCIAL_COUNT=$(python3 -c "import json; d=json.load(open('$AMOS_DIR/fiducials_export.json')); print(len(d.get('fiducials', [])))" 2>/dev/null || echo "0")
    FIDUCIAL_LABELS=$(python3 -c "import json; d=json.load(open('$AMOS_DIR/fiducials_export.json')); print('|'.join([f.get('label','') for f in d.get('fiducials', [])]))" 2>/dev/null || echo "")
fi

# Check for screenshots
AXIAL_EXISTS="false"
CORONAL_EXISTS="false"
SAGITTAL_EXISTS="false"
AXIAL_SIZE=0
CORONAL_SIZE=0
SAGITTAL_SIZE=0

AXIAL_PATHS=(
    "$AMOS_DIR/briefing_axial.png"
    "$AMOS_DIR/axial.png"
    "$AMOS_DIR/axial_view.png"
)

for path in "${AXIAL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AXIAL_EXISTS="true"
        AXIAL_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        if [ "$path" != "$AMOS_DIR/briefing_axial.png" ]; then
            cp "$path" "$AMOS_DIR/briefing_axial.png" 2>/dev/null || true
        fi
        break
    fi
done

CORONAL_PATHS=(
    "$AMOS_DIR/briefing_coronal.png"
    "$AMOS_DIR/coronal.png"
    "$AMOS_DIR/coronal_view.png"
)

for path in "${CORONAL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CORONAL_EXISTS="true"
        CORONAL_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        if [ "$path" != "$AMOS_DIR/briefing_coronal.png" ]; then
            cp "$path" "$AMOS_DIR/briefing_coronal.png" 2>/dev/null || true
        fi
        break
    fi
done

SAGITTAL_PATHS=(
    "$AMOS_DIR/briefing_sagittal.png"
    "$AMOS_DIR/sagittal.png"
    "$AMOS_DIR/sagittal_view.png"
)

for path in "${SAGITTAL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SAGITTAL_EXISTS="true"
        SAGITTAL_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        if [ "$path" != "$AMOS_DIR/briefing_sagittal.png" ]; then
            cp "$path" "$AMOS_DIR/briefing_sagittal.png" 2>/dev/null || true
        fi
        break
    fi
done

# Check for scene file
SCENE_EXISTS="false"
SCENE_PATH=""

for ext in mrml mrb; do
    FOUND_SCENE=$(find "$AMOS_DIR" -maxdepth 1 -name "*.$ext" -newer /tmp/task_start_iso.txt 2>/dev/null | head -1)
    if [ -n "$FOUND_SCENE" ]; then
        SCENE_EXISTS="true"
        SCENE_PATH="$FOUND_SCENE"
        echo "Found scene file: $SCENE_PATH"
        break
    fi
done

# Also check for any scene file regardless of timestamp
if [ "$SCENE_EXISTS" = "false" ]; then
    for ext in mrml mrb; do
        FOUND_SCENE=$(find "$AMOS_DIR" -maxdepth 1 -name "*.$ext" 2>/dev/null | head -1)
        if [ -n "$FOUND_SCENE" ]; then
            SCENE_EXISTS="true"
            SCENE_PATH="$FOUND_SCENE"
            echo "Found scene file (pre-existing): $SCENE_PATH"
            break
        fi
    done
fi

# Copy ground truth labels for verification
echo "Preparing ground truth for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" /tmp/gt_labels.nii.gz 2>/dev/null || true
chmod 644 /tmp/gt_labels.nii.gz 2>/dev/null || true

# Copy fiducial export for verification
if [ -f "$AMOS_DIR/fiducials_export.json" ]; then
    cp "$AMOS_DIR/fiducials_export.json" /tmp/fiducials_export.json 2>/dev/null || true
    chmod 644 /tmp/fiducials_export.json 2>/dev/null || true
fi

if [ -f "$AMOS_DIR/anatomical_landmarks.mrk.json" ]; then
    cp "$AMOS_DIR/anatomical_landmarks.mrk.json" /tmp/anatomical_landmarks.mrk.json 2>/dev/null || true
    chmod 644 /tmp/anatomical_landmarks.mrk.json 2>/dev/null || true
fi

# Copy screenshots for verification
for view in axial coronal sagittal; do
    if [ -f "$AMOS_DIR/briefing_${view}.png" ]; then
        cp "$AMOS_DIR/briefing_${view}.png" "/tmp/briefing_${view}.png" 2>/dev/null || true
        chmod 644 "/tmp/briefing_${view}.png" 2>/dev/null || true
    fi
done

# Get ground truth info for verification
GT_INFO=""
if [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" ]; then
    cp "$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json" /tmp/gt_info.json 2>/dev/null || true
    chmod 644 /tmp/gt_info.json 2>/dev/null || true
fi

# Create result JSON
TASK_END_TIME=$(date +%s)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END_TIME,
    "case_id": "$CASE_ID",
    "fiducials_exist": $FIDUCIALS_EXIST,
    "fiducial_count": $FIDUCIAL_COUNT,
    "fiducial_labels": "$FIDUCIAL_LABELS",
    "fiducial_path": "$FIDUCIAL_PATH",
    "axial_screenshot_exists": $AXIAL_EXISTS,
    "axial_screenshot_size": $AXIAL_SIZE,
    "coronal_screenshot_exists": $CORONAL_EXISTS,
    "coronal_screenshot_size": $CORONAL_SIZE,
    "sagittal_screenshot_exists": $SAGITTAL_EXISTS,
    "sagittal_screenshot_size": $SAGITTAL_SIZE,
    "scene_exists": $SCENE_EXISTS,
    "scene_path": "$SCENE_PATH",
    "ground_truth_labels_available": $([ -f "/tmp/gt_labels.nii.gz" ] && echo "true" || echo "false"),
    "final_screenshot_exists": $([ -f "/tmp/anatomy_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/anatomy_task_result.json 2>/dev/null || sudo rm -f /tmp/anatomy_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/anatomy_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/anatomy_task_result.json
chmod 666 /tmp/anatomy_task_result.json 2>/dev/null || sudo chmod 666 /tmp/anatomy_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/anatomy_task_result.json
echo ""
echo "=== Export Complete ==="