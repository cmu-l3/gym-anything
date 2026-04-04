#!/bin/bash
echo "=== Exporting Grow From Seeds Tumor Segmentation Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_SEG="$BRATS_DIR/tumor_segmentation.seg.nrrd"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get sample ID
SAMPLE_ID=$(cat /tmp/task_sample_id.txt 2>/dev/null || echo "BraTS2021_00000")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/grow_seeds_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export segmentation from Slicer via Python script
    echo "Attempting to export segmentation from Slicer..."
    
    cat > /tmp/export_segmentation.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Get all segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

segmentation_info = {
    "num_segmentation_nodes": len(seg_nodes),
    "segments": []
}

for seg_node in seg_nodes:
    seg = seg_node.GetSegmentation()
    num_segments = seg.GetNumberOfSegments()
    print(f"Segmentation '{seg_node.GetName()}' has {num_segments} segment(s)")
    
    for i in range(num_segments):
        segment_id = seg.GetNthSegmentID(i)
        segment = seg.GetSegment(segment_id)
        segment_name = segment.GetName()
        
        # Get segment statistics
        import numpy as np
        seg_array = slicer.util.arrayFromSegmentBinaryLabelmap(seg_node, segment_id)
        voxel_count = int(np.sum(seg_array > 0)) if seg_array is not None else 0
        
        seg_info = {
            "name": segment_name,
            "id": segment_id,
            "voxel_count": voxel_count
        }
        segmentation_info["segments"].append(seg_info)
        print(f"  Segment '{segment_name}': {voxel_count} voxels")
    
    # Export segmentation
    if num_segments > 0:
        # Try to export as seg.nrrd
        output_path = os.path.join(output_dir, "tumor_segmentation.seg.nrrd")
        success = slicer.util.saveNode(seg_node, output_path)
        print(f"Saved segmentation to {output_path}: {success}")
        
        # Also export as labelmap for easier verification
        labelmap_path = os.path.join(output_dir, "tumor_segmentation_labelmap.nii.gz")
        try:
            labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
            slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
                seg_node, labelmapNode, slicer.vtkSegmentation.EXTENT_REFERENCE_GEOMETRY)
            slicer.util.saveNode(labelmapNode, labelmap_path)
            print(f"Saved labelmap to {labelmap_path}")
            slicer.mrmlScene.RemoveNode(labelmapNode)
        except Exception as e:
            print(f"Could not export labelmap: {e}")

# Save info for verification
info_path = os.path.join(output_dir, "segmentation_info.json")
with open(info_path, "w") as f:
    json.dump(segmentation_info, f, indent=2)
print(f"Segmentation info saved to {info_path}")
PYEOF

    # Run the export script
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_segmentation.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Search for segmentation files
echo "Searching for segmentation files..."
SEG_FILE_FOUND="false"
SEG_FILE_PATH=""
SEG_FILE_SIZE=0

# Check various possible output locations
SEARCH_PATHS=(
    "$OUTPUT_SEG"
    "$BRATS_DIR/tumor_segmentation.nrrd"
    "$BRATS_DIR/tumor_segmentation.nii.gz"
    "$BRATS_DIR/tumor_segmentation_labelmap.nii.gz"
    "$BRATS_DIR/Segmentation.seg.nrrd"
    "/home/ga/Documents/tumor_segmentation.seg.nrrd"
    "/home/ga/tumor_segmentation.seg.nrrd"
)

for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_FILE_FOUND="true"
        SEG_FILE_PATH="$path"
        SEG_FILE_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        echo "Found segmentation file: $path ($SEG_FILE_SIZE bytes)"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Also check for any newly created .nrrd or .nii.gz files
NEW_SEG_FILES=$(find "$BRATS_DIR" /home/ga -maxdepth 2 -type f \( -name "*.seg.nrrd" -o -name "*segmentation*.nii.gz" -o -name "*Segmentation*.nrrd" \) -newer /tmp/task_start_time.txt 2>/dev/null | head -5)
if [ -n "$NEW_SEG_FILES" ]; then
    echo "New segmentation files since task start:"
    echo "$NEW_SEG_FILES"
    
    if [ "$SEG_FILE_FOUND" = "false" ]; then
        FIRST_NEW=$(echo "$NEW_SEG_FILES" | head -1)
        if [ -f "$FIRST_NEW" ]; then
            SEG_FILE_FOUND="true"
            SEG_FILE_PATH="$FIRST_NEW"
            SEG_FILE_SIZE=$(stat -c %s "$FIRST_NEW" 2>/dev/null || echo "0")
            cp "$FIRST_NEW" "$OUTPUT_SEG" 2>/dev/null || true
        fi
    fi
fi

# Check if file was created during task (anti-gaming)
FILE_CREATED_DURING_TASK="false"
if [ "$SEG_FILE_FOUND" = "true" ] && [ -f "$SEG_FILE_PATH" ]; then
    SEG_MTIME=$(stat -c %Y "$SEG_FILE_PATH" 2>/dev/null || echo "0")
    if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Segmentation was created during task"
    else
        echo "WARNING: Segmentation file existed before task start"
    fi
fi

# Read segmentation info if exported by Slicer
SEG_INFO_PATH="$BRATS_DIR/segmentation_info.json"
NUM_SEGMENTS=0
TUMOR_VOXELS=0

if [ -f "$SEG_INFO_PATH" ]; then
    NUM_SEGMENTS=$(python3 -c "import json; d=json.load(open('$SEG_INFO_PATH')); print(len(d.get('segments', [])))" 2>/dev/null || echo "0")
    TUMOR_VOXELS=$(python3 -c "
import json
d = json.load(open('$SEG_INFO_PATH'))
for seg in d.get('segments', []):
    name = seg.get('name', '').lower()
    if 'tumor' in name or 'tumour' in name:
        print(seg.get('voxel_count', 0))
        break
else:
    # If no 'tumor' named segment, use first non-zero segment
    for seg in d.get('segments', []):
        count = seg.get('voxel_count', 0)
        if count > 0:
            print(count)
            break
    else:
        print(0)
" 2>/dev/null || echo "0")
fi

# Analyze the segmentation file for metrics
echo "Analyzing segmentation..."
python3 << PYEOF
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

seg_path = "$SEG_FILE_PATH"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"
output_path = "/tmp/segmentation_analysis.json"

analysis = {
    "seg_file_found": os.path.exists(seg_path) if seg_path else False,
    "seg_path": seg_path,
    "tumor_voxels": 0,
    "tumor_volume_ml": 0,
    "centroid_ijk": [0, 0, 0],
    "in_brain_region": False,
    "dice_vs_enhancing": 0,
    "dice_vs_whole_tumor": 0,
    "sensitivity_enhancing": 0,
    "specificity": 0,
    "error": None
}

if not seg_path or not os.path.exists(seg_path):
    analysis["error"] = "Segmentation file not found"
    with open(output_path, "w") as f:
        json.dump(analysis, f, indent=2)
    print("No segmentation file to analyze")
    sys.exit(0)

try:
    # Load segmentation
    print(f"Loading segmentation from {seg_path}")
    
    # Handle different file formats
    if seg_path.endswith('.seg.nrrd'):
        # NRRD segmentation - may need special handling
        import nrrd
        seg_data, seg_header = nrrd.read(seg_path)
        # Convert to binary mask (any non-zero is tumor)
        seg_binary = (seg_data > 0).astype(np.int32)
        voxel_dims = [1.0, 1.0, 1.0]  # Default if not in header
        if 'space directions' in seg_header:
            sd = seg_header['space directions']
            voxel_dims = [np.linalg.norm(sd[i]) for i in range(3)]
    else:
        # NIfTI format
        seg_nii = nib.load(seg_path)
        seg_data = seg_nii.get_fdata()
        seg_binary = (seg_data > 0).astype(np.int32)
        voxel_dims = seg_nii.header.get_zooms()[:3]
    
    voxel_volume_mm3 = float(np.prod(voxel_dims))
    
    # Calculate metrics
    tumor_voxels = int(np.sum(seg_binary > 0))
    tumor_volume_ml = tumor_voxels * voxel_volume_mm3 / 1000
    
    analysis["tumor_voxels"] = tumor_voxels
    analysis["tumor_volume_ml"] = round(tumor_volume_ml, 2)
    analysis["voxel_dims_mm"] = [float(v) for v in voxel_dims]
    
    print(f"Tumor voxels: {tumor_voxels}")
    print(f"Tumor volume: {tumor_volume_ml:.2f} ml")
    
    # Get centroid
    if tumor_voxels > 0:
        coords = np.argwhere(seg_binary > 0)
        centroid = coords.mean(axis=0).tolist()
        analysis["centroid_ijk"] = [round(c, 1) for c in centroid]
        
        # Check if in brain region (rough check based on shape)
        shape = seg_data.shape
        center_region = (
            shape[0] * 0.1 < centroid[0] < shape[0] * 0.9 and
            shape[1] * 0.1 < centroid[1] < shape[1] * 0.9 and
            shape[2] * 0.1 < centroid[2] < shape[2] * 0.9
        )
        analysis["in_brain_region"] = center_region
    
    # Load ground truth for comparison
    gt_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
    if os.path.exists(gt_path):
        print(f"Loading ground truth from {gt_path}")
        gt_nii = nib.load(gt_path)
        gt_data = gt_nii.get_fdata().astype(np.int32)
        
        # BraTS labels: 1=necrotic, 2=edema, 4=enhancing
        gt_enhancing = (gt_data == 4)
        gt_whole_tumor = (gt_data > 0)
        
        # Resize seg_binary to match gt shape if needed
        if seg_binary.shape != gt_data.shape:
            print(f"Shape mismatch: seg {seg_binary.shape} vs gt {gt_data.shape}")
            # Try to use overlapping region
            min_shape = [min(s, g) for s, g in zip(seg_binary.shape, gt_data.shape)]
            seg_crop = seg_binary[:min_shape[0], :min_shape[1], :min_shape[2]]
            gt_enh_crop = gt_enhancing[:min_shape[0], :min_shape[1], :min_shape[2]]
            gt_wt_crop = gt_whole_tumor[:min_shape[0], :min_shape[1], :min_shape[2]]
        else:
            seg_crop = seg_binary
            gt_enh_crop = gt_enhancing
            gt_wt_crop = gt_whole_tumor
        
        # Calculate Dice coefficient vs enhancing tumor
        seg_flat = (seg_crop > 0).flatten()
        gt_enh_flat = gt_enh_crop.flatten()
        gt_wt_flat = gt_wt_crop.flatten()
        
        intersection_enh = np.sum(seg_flat & gt_enh_flat)
        dice_enh = 2 * intersection_enh / (np.sum(seg_flat) + np.sum(gt_enh_flat)) if (np.sum(seg_flat) + np.sum(gt_enh_flat)) > 0 else 0
        
        intersection_wt = np.sum(seg_flat & gt_wt_flat)
        dice_wt = 2 * intersection_wt / (np.sum(seg_flat) + np.sum(gt_wt_flat)) if (np.sum(seg_flat) + np.sum(gt_wt_flat)) > 0 else 0
        
        # Sensitivity (recall) for enhancing tumor
        sensitivity = intersection_enh / np.sum(gt_enh_flat) if np.sum(gt_enh_flat) > 0 else 0
        
        analysis["dice_vs_enhancing"] = round(float(dice_enh), 4)
        analysis["dice_vs_whole_tumor"] = round(float(dice_wt), 4)
        analysis["sensitivity_enhancing"] = round(float(sensitivity), 4)
        
        print(f"Dice (vs enhancing): {dice_enh:.4f}")
        print(f"Dice (vs whole tumor): {dice_wt:.4f}")
        print(f"Sensitivity: {sensitivity:.4f}")
    else:
        print(f"Ground truth not found at {gt_path}")
        analysis["error"] = "Ground truth not available for comparison"

except ImportError as e:
    # nrrd not available, try simpler check
    analysis["error"] = f"Missing dependency: {e}"
    print(f"Could not analyze: {e}")
except Exception as e:
    analysis["error"] = str(e)
    print(f"Error analyzing segmentation: {e}")

with open(output_path, "w") as f:
    json.dump(analysis, f, indent=2)
print(f"Analysis saved to {output_path}")
PYEOF

# Read analysis results
ANALYSIS_PATH="/tmp/segmentation_analysis.json"
DICE_ENHANCING="0"
DICE_WHOLE="0"
SENSITIVITY="0"
TUMOR_VOLUME_ML="0"
IN_BRAIN="false"

if [ -f "$ANALYSIS_PATH" ]; then
    DICE_ENHANCING=$(python3 -c "import json; print(json.load(open('$ANALYSIS_PATH')).get('dice_vs_enhancing', 0))" 2>/dev/null || echo "0")
    DICE_WHOLE=$(python3 -c "import json; print(json.load(open('$ANALYSIS_PATH')).get('dice_vs_whole_tumor', 0))" 2>/dev/null || echo "0")
    SENSITIVITY=$(python3 -c "import json; print(json.load(open('$ANALYSIS_PATH')).get('sensitivity_enhancing', 0))" 2>/dev/null || echo "0")
    TUMOR_VOLUME_ML=$(python3 -c "import json; print(json.load(open('$ANALYSIS_PATH')).get('tumor_volume_ml', 0))" 2>/dev/null || echo "0")
    IN_BRAIN=$(python3 -c "import json; v=json.load(open('$ANALYSIS_PATH')).get('in_brain_region', False); print('true' if v else 'false')" 2>/dev/null || echo "false")
    TUMOR_VOXELS=$(python3 -c "import json; print(json.load(open('$ANALYSIS_PATH')).get('tumor_voxels', 0))" 2>/dev/null || echo "0")
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_file_found": $SEG_FILE_FOUND,
    "segmentation_file_path": "$SEG_FILE_PATH",
    "segmentation_file_size": $SEG_FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "num_segments": $NUM_SEGMENTS,
    "tumor_voxels": $TUMOR_VOXELS,
    "tumor_volume_ml": $TUMOR_VOLUME_ML,
    "in_brain_region": $IN_BRAIN,
    "dice_vs_enhancing": $DICE_ENHANCING,
    "dice_vs_whole_tumor": $DICE_WHOLE,
    "sensitivity": $SENSITIVITY,
    "screenshot_exists": $([ -f /tmp/grow_seeds_final.png ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/grow_seeds_task_result.json 2>/dev/null || sudo rm -f /tmp/grow_seeds_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/grow_seeds_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/grow_seeds_task_result.json
chmod 666 /tmp/grow_seeds_task_result.json 2>/dev/null || sudo chmod 666 /tmp/grow_seeds_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/grow_seeds_task_result.json"
cat /tmp/grow_seeds_task_result.json
echo ""
echo "=== Export Complete ==="