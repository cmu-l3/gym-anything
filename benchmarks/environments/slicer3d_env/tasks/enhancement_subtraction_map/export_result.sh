#!/bin/bash
echo "=== Exporting Enhancement Subtraction Map Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MAP="$BRATS_DIR/enhancement_map.nii.gz"
OUTPUT_MASK="$BRATS_DIR/enhancement_mask.nii.gz"
OUTPUT_REPORT="$BRATS_DIR/enhancement_report.txt"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/enhancement_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export any volumes created during the task
    cat > /tmp/export_enhancement_volumes.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

exported = []

# Look for enhancement map volume
for name in ["EnhancementMap", "enhancement_map", "Enhancement", "Subtraction", "subtraction", "T1ce-T1", "T1_Contrast-T1"]:
    try:
        node = slicer.util.getNode(name)
        if node:
            save_path = os.path.join(output_dir, "enhancement_map.nii.gz")
            success = slicer.util.saveNode(node, save_path)
            if success:
                print(f"Exported enhancement map: {name} -> {save_path}")
                exported.append({"name": name, "type": "enhancement_map", "path": save_path})
            break
    except:
        continue

# Look for enhancement mask (could be segmentation or label map)
for name in ["EnhancementMask", "enhancement_mask", "Enhancement Mask", "ThresholdedEnhancement", "mask"]:
    try:
        node = slicer.util.getNode(name)
        if node:
            save_path = os.path.join(output_dir, "enhancement_mask.nii.gz")
            success = slicer.util.saveNode(node, save_path)
            if success:
                print(f"Exported enhancement mask: {name} -> {save_path}")
                exported.append({"name": name, "type": "enhancement_mask", "path": save_path})
            break
    except:
        continue

# Also check segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
for seg_node in seg_nodes:
    seg_name = seg_node.GetName()
    if "enhancement" in seg_name.lower() or "mask" in seg_name.lower():
        save_path = os.path.join(output_dir, "enhancement_mask.nii.gz")
        # Export as label map
        labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
        slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(seg_node, labelmapNode)
        success = slicer.util.saveNode(labelmapNode, save_path)
        if success:
            print(f"Exported segmentation as mask: {seg_name} -> {save_path}")
            exported.append({"name": seg_name, "type": "segmentation_mask", "path": save_path})
        slicer.mrmlScene.RemoveNode(labelmapNode)
        break

# List all volumes for debugging
print("\nAll volumes in scene:")
for node in slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode"):
    print(f"  - {node.GetName()}")

print(f"\nExported {len(exported)} items")
PYEOF

    # Run the export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_enhancement_volumes.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 15
    pkill -f "export_enhancement_volumes" 2>/dev/null || true
fi

# Check if enhancement map exists
ENHANCEMENT_MAP_EXISTS="false"
ENHANCEMENT_MAP_PATH=""
ENHANCEMENT_MAP_SIZE=0
ENHANCEMENT_MAP_CREATED_DURING_TASK="false"

POSSIBLE_MAP_PATHS=(
    "$OUTPUT_MAP"
    "$BRATS_DIR/EnhancementMap.nii.gz"
    "$BRATS_DIR/enhancement_map.nii"
    "$BRATS_DIR/subtraction.nii.gz"
    "/home/ga/Documents/enhancement_map.nii.gz"
)

for path in "${POSSIBLE_MAP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        ENHANCEMENT_MAP_EXISTS="true"
        ENHANCEMENT_MAP_PATH="$path"
        ENHANCEMENT_MAP_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            ENHANCEMENT_MAP_CREATED_DURING_TASK="true"
        fi
        
        echo "Found enhancement map at: $path (size: $ENHANCEMENT_MAP_SIZE bytes)"
        if [ "$path" != "$OUTPUT_MAP" ]; then
            cp "$path" "$OUTPUT_MAP" 2>/dev/null || true
        fi
        break
    fi
done

# Check if enhancement mask exists
ENHANCEMENT_MASK_EXISTS="false"
ENHANCEMENT_MASK_PATH=""
ENHANCEMENT_MASK_SIZE=0
ENHANCEMENT_MASK_CREATED_DURING_TASK="false"

POSSIBLE_MASK_PATHS=(
    "$OUTPUT_MASK"
    "$BRATS_DIR/EnhancementMask.nii.gz"
    "$BRATS_DIR/enhancement_mask.nii"
    "$BRATS_DIR/mask.nii.gz"
    "/home/ga/Documents/enhancement_mask.nii.gz"
)

for path in "${POSSIBLE_MASK_PATHS[@]}"; do
    if [ -f "$path" ]; then
        ENHANCEMENT_MASK_EXISTS="true"
        ENHANCEMENT_MASK_PATH="$path"
        ENHANCEMENT_MASK_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            ENHANCEMENT_MASK_CREATED_DURING_TASK="true"
        fi
        
        echo "Found enhancement mask at: $path (size: $ENHANCEMENT_MASK_SIZE bytes)"
        if [ "$path" != "$OUTPUT_MASK" ]; then
            cp "$path" "$OUTPUT_MASK" 2>/dev/null || true
        fi
        break
    fi
done

# Check if report exists
REPORT_EXISTS="false"
REPORTED_VOLUME=""
REPORTED_MAX_INTENSITY=""
REPORTED_MEAN_INTENSITY=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.txt"
    "$BRATS_DIR/enhancement_report.txt"
    "/home/ga/Documents/enhancement_report.txt"
    "/home/ga/enhancement_report.txt"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract metrics from report
        REPORT_CONTENT=$(cat "$path" 2>/dev/null || echo "")
        
        # Try to extract volume (look for mL or ml)
        REPORTED_VOLUME=$(echo "$REPORT_CONTENT" | grep -ioE '[0-9]+\.?[0-9]*\s*(mL|ml|milliliters?)' | head -1 | grep -oE '[0-9]+\.?[0-9]*' || echo "")
        if [ -z "$REPORTED_VOLUME" ]; then
            # Look for "volume" keyword followed by number
            REPORTED_VOLUME=$(echo "$REPORT_CONTENT" | grep -i "volume" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "")
        fi
        
        # Try to extract max intensity
        REPORTED_MAX_INTENSITY=$(echo "$REPORT_CONTENT" | grep -i "max" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "")
        
        # Try to extract mean intensity
        REPORTED_MEAN_INTENSITY=$(echo "$REPORT_CONTENT" | grep -i "mean" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "")
        
        echo "Extracted from report: volume=$REPORTED_VOLUME mL, max=$REPORTED_MAX_INTENSITY, mean=$REPORTED_MEAN_INTENSITY"
        break
    fi
done

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy files for verification
echo "Preparing files for verification..."

# Copy ground truth files
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_subtraction_gt.nii.gz" /tmp/gt_subtraction.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_enhancement_gt.json" /tmp/gt_enhancement_metrics.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/gt_segmentation.nii.gz 2>/dev/null || true
chmod 644 /tmp/gt_*.* 2>/dev/null || true

# Copy agent outputs
if [ -f "$OUTPUT_MAP" ]; then
    cp "$OUTPUT_MAP" /tmp/agent_enhancement_map.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_enhancement_map.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_MASK" ]; then
    cp "$OUTPUT_MASK" /tmp/agent_enhancement_mask.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_enhancement_mask.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.txt 2>/dev/null || true
    chmod 644 /tmp/agent_report.txt 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "enhancement_map_exists": $ENHANCEMENT_MAP_EXISTS,
    "enhancement_map_path": "$ENHANCEMENT_MAP_PATH",
    "enhancement_map_size_bytes": $ENHANCEMENT_MAP_SIZE,
    "enhancement_map_created_during_task": $ENHANCEMENT_MAP_CREATED_DURING_TASK,
    "enhancement_mask_exists": $ENHANCEMENT_MASK_EXISTS,
    "enhancement_mask_path": "$ENHANCEMENT_MASK_PATH",
    "enhancement_mask_size_bytes": $ENHANCEMENT_MASK_SIZE,
    "enhancement_mask_created_during_task": $ENHANCEMENT_MASK_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "reported_volume_ml": "$REPORTED_VOLUME",
    "reported_max_intensity": "$REPORTED_MAX_INTENSITY",
    "reported_mean_intensity": "$REPORTED_MEAN_INTENSITY",
    "sample_id": "$SAMPLE_ID",
    "screenshot_exists": $([ -f "/tmp/enhancement_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/enhancement_task_result.json 2>/dev/null || sudo rm -f /tmp/enhancement_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/enhancement_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/enhancement_task_result.json
chmod 666 /tmp/enhancement_task_result.json 2>/dev/null || sudo chmod 666 /tmp/enhancement_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/enhancement_task_result.json
echo ""
echo "=== Export Complete ==="