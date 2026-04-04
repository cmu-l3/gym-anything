#!/bin/bash
echo "=== Exporting Expand Surgical Margin Results ==="

source /workspace/scripts/task_utils.sh

# Get config
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
EXPECTED_OUTPUT="$BRATS_DIR/surgical_margin_segmentation.seg.nrrd"
INITIAL_SEG="$BRATS_DIR/initial_tumor_segmentation.seg.nrrd"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/margin_task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to save segmentation from Slicer if not already saved
    echo "Attempting to export segmentation from Slicer..."
    cat > /tmp/export_margin_seg.py << 'PYEOF'
import slicer
import os

output_dir = "/home/ga/Documents/SlicerData/BraTS"
output_path = os.path.join(output_dir, "surgical_margin_segmentation.seg.nrrd")

# Find segmentation nodes
segNodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(segNodes)} segmentation node(s)")

for segNode in segNodes:
    name = segNode.GetName()
    print(f"  Segmentation: {name}")
    seg = segNode.GetSegmentation()
    if seg:
        n_segments = seg.GetNumberOfSegments()
        print(f"    Segments: {n_segments}")
        for i in range(n_segments):
            segId = seg.GetNthSegmentID(i)
            segment = seg.GetSegment(segId)
            print(f"      - {segment.GetName()}")

# Find the tumor segmentation and save it
for segNode in segNodes:
    if "Tumor" in segNode.GetName() or "tumor" in segNode.GetName():
        print(f"Saving segmentation: {segNode.GetName()} to {output_path}")
        slicer.util.saveNode(segNode, output_path)
        print("Save complete")
        break

print("Export script finished")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_margin_seg.py --no-main-window > /tmp/slicer_margin_export.log 2>&1 &
    sleep 10
    pkill -f "export_margin_seg" 2>/dev/null || true
fi

# Check if output file exists
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $EXPECTED_OUTPUT (${OUTPUT_SIZE} bytes)"
else
    echo "Output file NOT found at $EXPECTED_OUTPUT"
    
    # Search for any .nrrd files that might be the output
    echo "Searching for alternative segmentation files..."
    find "$BRATS_DIR" -name "*.nrrd" -o -name "*.seg.nrrd" 2>/dev/null | head -5
fi

# Calculate volume metrics using Python
echo "Computing volume metrics..."

python3 << PYEOF
import os
import sys
import json

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

try:
    import nrrd
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pynrrd"])
    import nrrd

from scipy.ndimage import distance_transform_edt
from scipy import ndimage

initial_path = "$INITIAL_SEG"
output_path = "$EXPECTED_OUTPUT"
gt_dir = "$GROUND_TRUTH_DIR"
sample_id = "$SAMPLE_ID"
task_start = int("$TASK_START")
task_end = int("$TASK_END")

result = {
    "task_start": task_start,
    "task_end": task_end,
    "slicer_was_running": "$SLICER_RUNNING" == "true",
    "output_exists": "$OUTPUT_EXISTS" == "true",
    "output_size_bytes": int("$OUTPUT_SIZE"),
    "file_created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
    "sample_id": sample_id
}

# Load initial segmentation
initial_volume_mm3 = 0
initial_voxel_count = 0
voxel_volume_mm3 = 1.0
spacing = [1.0, 1.0, 1.0]

if os.path.exists(initial_path):
    try:
        initial_data, initial_header = nrrd.read(initial_path)
        initial_mask = (initial_data > 0).astype(np.uint8)
        initial_voxel_count = int(np.sum(initial_mask))
        
        # Get spacing from header
        if 'space directions' in initial_header:
            sd = initial_header['space directions']
            spacing = [abs(sd[0][0]), abs(sd[1][1]), abs(sd[2][2])]
        elif 'spacings' in initial_header:
            spacing = list(initial_header['spacings'])
        
        voxel_volume_mm3 = float(np.prod(spacing))
        initial_volume_mm3 = initial_voxel_count * voxel_volume_mm3
        
        result["initial_voxel_count"] = initial_voxel_count
        result["initial_volume_mm3"] = initial_volume_mm3
        result["initial_volume_ml"] = initial_volume_mm3 / 1000.0
        result["voxel_spacing_mm"] = spacing
        print(f"Initial segmentation: {initial_voxel_count} voxels, {initial_volume_mm3/1000:.2f} mL")
    except Exception as e:
        print(f"Error loading initial segmentation: {e}")
        result["initial_load_error"] = str(e)

# Load expanded segmentation
if os.path.exists(output_path):
    try:
        output_data, output_header = nrrd.read(output_path)
        
        # Handle Slicer segmentation format (may have multiple labels)
        if output_data.ndim == 4:
            # Multi-segment format - combine all
            output_mask = np.any(output_data > 0, axis=-1).astype(np.uint8)
        else:
            output_mask = (output_data > 0).astype(np.uint8)
        
        output_voxel_count = int(np.sum(output_mask))
        
        # Get spacing from output header if different
        output_spacing = spacing
        if 'space directions' in output_header:
            sd = output_header['space directions']
            if isinstance(sd[0], (list, tuple)):
                output_spacing = [abs(sd[0][0]), abs(sd[1][1]), abs(sd[2][2])]
        
        output_voxel_volume = float(np.prod(output_spacing))
        output_volume_mm3 = output_voxel_count * output_voxel_volume
        
        result["output_voxel_count"] = output_voxel_count
        result["output_volume_mm3"] = output_volume_mm3
        result["output_volume_ml"] = output_volume_mm3 / 1000.0
        result["output_spacing_mm"] = output_spacing
        
        print(f"Output segmentation: {output_voxel_count} voxels, {output_volume_mm3/1000:.2f} mL")
        
        # Calculate volume ratio
        if initial_volume_mm3 > 0:
            volume_ratio = output_volume_mm3 / initial_volume_mm3
            result["volume_ratio"] = volume_ratio
            result["volume_increase_mm3"] = output_volume_mm3 - initial_volume_mm3
            result["volume_increase_ml"] = (output_volume_mm3 - initial_volume_mm3) / 1000.0
            print(f"Volume ratio: {volume_ratio:.2f}x")
        
        # Calculate surface distance (margin estimate)
        # This is computationally intensive, so sample if large
        if os.path.exists(initial_path) and initial_voxel_count > 0:
            try:
                # Resize for faster computation if needed
                max_size = 128
                if max(initial_mask.shape) > max_size:
                    factor = max_size / max(initial_mask.shape)
                    from scipy.ndimage import zoom
                    initial_small = zoom(initial_mask, factor, order=0)
                    output_small = zoom(output_mask[:initial_mask.shape[0], :initial_mask.shape[1], :initial_mask.shape[2]], factor, order=0)
                    effective_spacing = [s / factor for s in spacing]
                else:
                    initial_small = initial_mask
                    output_small = output_mask[:initial_mask.shape[0], :initial_mask.shape[1], :initial_mask.shape[2]]
                    effective_spacing = spacing
                
                # Distance transform from initial surface
                initial_surface = initial_small & ~ndimage.binary_erosion(initial_small)
                
                # Distance from initial to expanded boundary
                expanded_boundary = output_small & ~ndimage.binary_erosion(output_small)
                
                # For points on expanded boundary that are outside initial,
                # measure distance to initial surface
                dt_from_initial = distance_transform_edt(~initial_small, sampling=effective_spacing)
                
                # Get distances at expanded boundary
                boundary_distances = dt_from_initial[expanded_boundary > 0]
                
                if len(boundary_distances) > 0:
                    mean_distance = float(np.mean(boundary_distances))
                    median_distance = float(np.median(boundary_distances))
                    min_distance = float(np.min(boundary_distances))
                    max_distance = float(np.max(boundary_distances))
                    
                    result["surface_distance_mean_mm"] = mean_distance
                    result["surface_distance_median_mm"] = median_distance
                    result["surface_distance_min_mm"] = min_distance
                    result["surface_distance_max_mm"] = max_distance
                    
                    print(f"Surface distance: mean={mean_distance:.1f}mm, median={median_distance:.1f}mm")
                    
            except Exception as e:
                print(f"Error computing surface distance: {e}")
                result["surface_distance_error"] = str(e)
        
        # Check if expanded contains original (topology check)
        if os.path.exists(initial_path) and initial_voxel_count > 0:
            try:
                # Crop to same size
                min_shape = tuple(min(a, b) for a, b in zip(initial_mask.shape, output_mask.shape))
                init_crop = initial_mask[:min_shape[0], :min_shape[1], :min_shape[2]]
                out_crop = output_mask[:min_shape[0], :min_shape[1], :min_shape[2]]
                
                overlap = np.sum(init_crop & out_crop)
                coverage = overlap / np.sum(init_crop) if np.sum(init_crop) > 0 else 0
                result["original_coverage"] = float(coverage)
                result["expanded_contains_original"] = coverage > 0.9
                print(f"Original coverage by expanded: {coverage*100:.1f}%")
            except Exception as e:
                print(f"Error checking topology: {e}")
        
    except Exception as e:
        print(f"Error loading output segmentation: {e}")
        result["output_load_error"] = str(e)
else:
    print("Output segmentation file not found")
    result["output_load_error"] = "File not found"

# Load ground truth metrics
gt_metrics_path = os.path.join(gt_dir, f"{sample_id}_margin_metrics.json")
if os.path.exists(gt_metrics_path):
    try:
        with open(gt_metrics_path) as f:
            gt_metrics = json.load(f)
        result["gt_initial_volume_mm3"] = gt_metrics.get("initial_volume_mm3", 0)
        result["expected_volume_ratio"] = gt_metrics.get("expected_volume_ratio_spherical", 2.0)
    except Exception as e:
        print(f"Error loading GT metrics: {e}")

# Save result
result_path = "/tmp/margin_task_result.json"
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"\nResult saved to {result_path}")
PYEOF

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Ensure result file has correct permissions
chmod 666 /tmp/margin_task_result.json 2>/dev/null || sudo chmod 666 /tmp/margin_task_result.json 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
cat /tmp/margin_task_result.json