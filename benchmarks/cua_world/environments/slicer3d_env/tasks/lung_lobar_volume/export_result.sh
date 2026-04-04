#!/bin/bash
echo "=== Exporting Lung Lobar Volume Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
PATIENT_ID="LIDC-IDRI-0001"
if [ -f /tmp/lung_lobar_patient_id.txt ]; then
    PATIENT_ID=$(cat /tmp/lung_lobar_patient_id.txt)
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_SEG="$LIDC_DIR/lobar_segmentation.nii.gz"
OUTPUT_REPORT="$LIDC_DIR/lobar_volumes.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/lung_lobar_final.png ga
sleep 1

# Check task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export segmentation from Slicer
    cat > /tmp/export_lobar_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    n_segments = seg_node.GetSegmentation().GetNumberOfSegments()
    print(f"  {seg_node.GetName()}: {n_segments} segments")
    
    if n_segments >= 2:  # At least left and right lungs
        # Export to labelmap
        output_path = os.path.join(output_dir, "lobar_segmentation.nii.gz")
        
        labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
        slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
            seg_node, labelmapNode
        )
        slicer.util.saveNode(labelmapNode, output_path)
        slicer.mrmlScene.RemoveNode(labelmapNode)
        print(f"Exported segmentation to {output_path}")
        
        # Try to calculate volumes
        volumes = {}
        seg = seg_node.GetSegmentation()
        for i in range(seg.GetNumberOfSegments()):
            segment = seg.GetNthSegment(i)
            seg_id = seg.GetNthSegmentID(i)
            seg_name = segment.GetName()
            
            # Get statistics using SegmentStatistics
            import SegmentStatistics
            stats = SegmentStatistics.SegmentStatisticsLogic()
            stats.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
            stats.getParameterNode().SetParameter("LabelmapSegmentStatisticsPlugin.enabled", "True")
            stats.computeStatistics()
            
            # Get volume
            volume_key = f"{seg_id}.LabelmapSegmentStatisticsPlugin.volume_cm3"
            volume_cm3 = stats.getStatistics().get(volume_key, 0)
            volumes[seg_name] = float(volume_cm3) * 1000  # Convert to mL
            print(f"    {seg_name}: {float(volume_cm3) * 1000:.1f} mL")
        
        # Save volumes report
        if volumes:
            report_path = os.path.join(output_dir, "lobar_volumes.json")
            total = sum(volumes.values())
            
            # Map to standard names if possible
            report = {
                "volumes_ml": volumes,
                "total_lung_volume_ml": total,
            }
            
            # Try to identify R/L ratio
            right_vol = 0
            left_vol = 0
            for name, vol in volumes.items():
                name_lower = name.lower()
                if 'right' in name_lower or name_lower.startswith('r'):
                    right_vol += vol
                elif 'left' in name_lower or name_lower.startswith('l'):
                    left_vol += vol
            
            if right_vol > 0 and left_vol > 0:
                report["right_lung_volume_ml"] = right_vol
                report["left_lung_volume_ml"] = left_vol
                report["right_left_ratio"] = right_vol / left_vol
            
            with open(report_path, "w") as f:
                json.dump(report, f, indent=2)
            print(f"Saved volume report to {report_path}")
        
        break

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_lobar_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 15
    pkill -f "export_lobar_seg" 2>/dev/null || true
fi

# Check for segmentation file
SEG_EXISTS="false"
SEG_PATH=""
SEG_SIZE=0
SEG_MODIFIED_DURING_TASK="false"

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$LIDC_DIR/Segmentation.nii.gz"
    "$LIDC_DIR/segmentation.nii.gz"
    "$LIDC_DIR/lung_segmentation.nii.gz"
    "/home/ga/Documents/lobar_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_EXISTS="true"
        SEG_PATH="$path"
        SEG_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            SEG_MODIFIED_DURING_TASK="true"
        fi
        
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        echo "Found segmentation at: $path (${SEG_SIZE} bytes)"
        break
    fi
done

# Check for volume report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_TOTAL_VOLUME=""
REPORTED_RL_RATIO=""
REPORTED_LOBE_COUNT=0

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/volumes.json"
    "$LIDC_DIR/lung_volumes.json"
    "/home/ga/Documents/lobar_volumes.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_TOTAL_VOLUME=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('total_lung_volume_ml', sum(d.get('volumes_ml', {}).values()) if 'volumes_ml' in d else 0))" 2>/dev/null || echo "")
        REPORTED_RL_RATIO=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('right_left_ratio', ''))" 2>/dev/null || echo "")
        REPORTED_LOBE_COUNT=$(python3 -c "import json; d=json.load(open('$path')); print(len(d.get('volumes_ml', d)))" 2>/dev/null || echo "0")
        
        echo "Found report at: $path"
        echo "  Total volume: $REPORTED_TOTAL_VOLUME mL"
        echo "  R/L ratio: $REPORTED_RL_RATIO"
        echo "  Lobe count: $REPORTED_LOBE_COUNT"
        break
    fi
done

# Analyze segmentation if it exists
LOBE_INFO="{}"
if [ "$SEG_EXISTS" = "true" ] && [ -f "$OUTPUT_SEG" ]; then
    echo "Analyzing segmentation..."
    
    LOBE_INFO=$(python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    print("{}")
    sys.exit(0)

seg_path = "/home/ga/Documents/SlicerData/LIDC/lobar_segmentation.nii.gz"
if not os.path.exists(seg_path):
    print("{}")
    sys.exit(0)

try:
    seg_nii = nib.load(seg_path)
    seg_data = seg_nii.get_fdata().astype(np.int32)
    spacing = seg_nii.header.get_zooms()[:3]
    voxel_volume_ml = float(np.prod(spacing)) / 1000.0
    
    unique_labels = np.unique(seg_data)
    unique_labels = unique_labels[unique_labels > 0]  # Exclude background
    
    lobe_info = {
        "unique_labels": [int(l) for l in unique_labels],
        "num_lobes": len(unique_labels),
        "voxel_volume_ml": voxel_volume_ml,
        "lobes": {}
    }
    
    for label in unique_labels:
        mask = (seg_data == label)
        voxel_count = np.sum(mask)
        volume_ml = voxel_count * voxel_volume_ml
        
        # Calculate centroid in mm
        coords = np.array(np.where(mask))
        if coords.size > 0:
            centroid_voxels = coords.mean(axis=1)
            centroid_mm = centroid_voxels * np.array(spacing)
        else:
            centroid_mm = [0, 0, 0]
        
        lobe_info["lobes"][str(label)] = {
            "volume_ml": float(volume_ml),
            "voxel_count": int(voxel_count),
            "centroid_mm": [float(c) for c in centroid_mm]
        }
    
    # Calculate total volume
    total_volume = sum(l["volume_ml"] for l in lobe_info["lobes"].values())
    lobe_info["total_volume_ml"] = total_volume
    
    # Determine laterality based on x-coordinate of centroids
    # Assume image center divides left from right
    shape = seg_data.shape
    center_x = shape[0] / 2.0 * spacing[0]
    
    right_lobes = []
    left_lobes = []
    for label, info in lobe_info["lobes"].items():
        cx = info["centroid_mm"][0]
        if cx < center_x:
            right_lobes.append(label)
        else:
            left_lobes.append(label)
    
    lobe_info["right_lobe_labels"] = right_lobes
    lobe_info["left_lobe_labels"] = left_lobes
    lobe_info["right_lobe_count"] = len(right_lobes)
    lobe_info["left_lobe_count"] = len(left_lobes)
    
    # Calculate R/L volume ratio
    right_vol = sum(lobe_info["lobes"][l]["volume_ml"] for l in right_lobes)
    left_vol = sum(lobe_info["lobes"][l]["volume_ml"] for l in left_lobes)
    lobe_info["right_volume_ml"] = right_vol
    lobe_info["left_volume_ml"] = left_vol
    lobe_info["rl_ratio"] = right_vol / left_vol if left_vol > 0 else 0
    
    print(json.dumps(lobe_info))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)
fi

# Copy ground truth for verification
echo "Preparing ground truth for verification..."
GT_FILE="$GROUND_TRUTH_DIR/${PATIENT_ID}_lobar_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/lung_lobar_gt.json 2>/dev/null || true
    chmod 644 /tmp/lung_lobar_gt.json 2>/dev/null || true
fi

if [ -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_lobar_gt.nii.gz" ]; then
    cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_lobar_gt.nii.gz" /tmp/lung_lobar_gt_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/lung_lobar_gt_seg.nii.gz 2>/dev/null || true
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
    "segmentation_exists": $SEG_EXISTS,
    "segmentation_path": "$SEG_PATH",
    "segmentation_size_bytes": $SEG_SIZE,
    "segmentation_modified_during_task": $SEG_MODIFIED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "reported_total_volume_ml": "$REPORTED_TOTAL_VOLUME",
    "reported_rl_ratio": "$REPORTED_RL_RATIO",
    "reported_lobe_count": $REPORTED_LOBE_COUNT,
    "lobe_analysis": $LOBE_INFO,
    "screenshot_exists": $([ -f "/tmp/lung_lobar_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/lung_lobar_gt.json" ] && echo "true" || echo "false"),
    "patient_id": "$PATIENT_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/lung_lobar_task_result.json 2>/dev/null || sudo rm -f /tmp/lung_lobar_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/lung_lobar_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/lung_lobar_task_result.json
chmod 666 /tmp/lung_lobar_task_result.json 2>/dev/null || sudo chmod 666 /tmp/lung_lobar_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/lung_lobar_task_result.json
echo ""
echo "=== Export Complete ==="