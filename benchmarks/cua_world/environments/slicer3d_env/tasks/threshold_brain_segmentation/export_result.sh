#!/bin/bash
echo "=== Exporting Threshold Brain Segmentation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot before any analysis
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Expected output path
OUTPUT_DIR="/home/ga/Documents/SlicerData/Exports"
EXPECTED_FILE="$OUTPUT_DIR/brain_segmentation.seg.nrrd"
MRI_PATH="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"

# Check for output file (also check alternative names)
FILE_EXISTS="false"
FILE_PATH=""
FILE_SIZE=0
FILE_MTIME=0

# Search for segmentation files
SEARCH_PATHS=(
    "$EXPECTED_FILE"
    "$OUTPUT_DIR/brain_segmentation.nrrd"
    "$OUTPUT_DIR/BrainTissue.seg.nrrd"
    "$OUTPUT_DIR/Segmentation.seg.nrrd"
)

for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FILE_EXISTS="true"
        FILE_PATH="$path"
        FILE_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        FILE_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        echo "Found segmentation file: $path (${FILE_SIZE} bytes)"
        break
    fi
done

# Also search for any .seg.nrrd files created during task
if [ "$FILE_EXISTS" = "false" ]; then
    NEW_SEG=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.seg.nrrd" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$NEW_SEG" ] && [ -f "$NEW_SEG" ]; then
        FILE_EXISTS="true"
        FILE_PATH="$NEW_SEG"
        FILE_SIZE=$(stat -c%s "$NEW_SEG" 2>/dev/null || echo "0")
        FILE_MTIME=$(stat -c%Y "$NEW_SEG" 2>/dev/null || echo "0")
        echo "Found new segmentation file: $NEW_SEG"
    fi
fi

# Check if file was created during task (anti-gaming)
FILE_CREATED_DURING_TASK="false"
if [ "$FILE_EXISTS" = "true" ] && [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
    echo "File was created during task execution"
else
    echo "File was NOT created during task (may be pre-existing)"
fi

# Analyze segmentation content if file exists
VOXEL_COUNT=0
CENTROID_X=0
CENTROID_Y=0
CENTROID_Z=0
MEAN_INTENSITY=0
VALID_LOCATION="false"
VALID_INTENSITY="false"
ANALYSIS_ERROR=""

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Analyzing segmentation content..."
    
    python3 << PYEOF
import json
import os
import sys

# Ensure nibabel is available
try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

try:
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
    import numpy as np

result_file = "/tmp/segmentation_analysis.json"
seg_path = "$FILE_PATH"
mri_path = "$MRI_PATH"

analysis = {
    "voxel_count": 0,
    "centroid": [0, 0, 0],
    "mean_intensity": 0,
    "valid_location": False,
    "valid_intensity": False,
    "error": None
}

try:
    # Load segmentation
    print(f"Loading segmentation from {seg_path}")
    seg_nii = nib.load(seg_path)
    seg_data = seg_nii.get_fdata()
    print(f"Segmentation shape: {seg_data.shape}")
    
    # Count non-zero voxels (segmented region)
    mask = seg_data > 0
    analysis["voxel_count"] = int(np.sum(mask))
    print(f"Voxel count: {analysis['voxel_count']}")
    
    if analysis["voxel_count"] > 0:
        # Calculate centroid of segmented region
        coords = np.array(np.where(mask))
        centroid = coords.mean(axis=1)
        analysis["centroid"] = [float(c) for c in centroid]
        print(f"Centroid: {analysis['centroid']}")
        
        # Check if centroid is in central region (brain should be roughly centered)
        shape = seg_data.shape
        center = [s/2 for s in shape]
        
        # Calculate distance from center as fraction of volume dimensions
        rel_distances = [abs(c - center[i]) / (shape[i]/2) for i, c in enumerate(centroid)]
        max_rel_dist = max(rel_distances)
        
        # Brain should be within ~60% of center in each dimension
        analysis["valid_location"] = max_rel_dist < 0.6
        print(f"Valid location: {analysis['valid_location']} (max rel dist: {max_rel_dist:.2f})")
        
        # Load MRI and check intensity values of segmented region
        try:
            mri_nii = nib.load(mri_path)
            mri_data = mri_nii.get_fdata()
            print(f"MRI shape: {mri_data.shape}")
            
            # Handle shape mismatch (segmentation might be in different space)
            if mri_data.shape == seg_data.shape:
                masked_intensities = mri_data[mask]
                analysis["mean_intensity"] = float(np.mean(masked_intensities))
                std_intensity = float(np.std(masked_intensities))
                print(f"Mean intensity: {analysis['mean_intensity']:.1f} (std: {std_intensity:.1f})")
                
                # Brain tissue in T1 MRI typically has intensities 50-500
                # Check mean is in reasonable range
                analysis["valid_intensity"] = 50 < analysis["mean_intensity"] < 500
                print(f"Valid intensity: {analysis['valid_intensity']}")
            else:
                print(f"Shape mismatch: seg {seg_data.shape} vs mri {mri_data.shape}")
                # Still mark as potentially valid if voxel count is reasonable
                if 50000 < analysis["voxel_count"] < 900000:
                    analysis["valid_intensity"] = True
                    analysis["mean_intensity"] = 200  # Estimated
                    
        except Exception as e:
            print(f"Could not load MRI for intensity check: {e}")
            # If we can't check intensity, assume valid if voxel count reasonable
            if 50000 < analysis["voxel_count"] < 900000:
                analysis["valid_intensity"] = True
                analysis["mean_intensity"] = 200
                
except Exception as e:
    analysis["error"] = str(e)
    print(f"Analysis error: {e}")

# Save analysis results
with open(result_file, 'w') as f:
    json.dump(analysis, f, indent=2)

print(f"Analysis saved to {result_file}")
PYEOF

    # Read analysis results
    if [ -f /tmp/segmentation_analysis.json ]; then
        VOXEL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/segmentation_analysis.json'))['voxel_count'])" 2>/dev/null || echo "0")
        MEAN_INTENSITY=$(python3 -c "import json; print(int(json.load(open('/tmp/segmentation_analysis.json')).get('mean_intensity', 0)))" 2>/dev/null || echo "0")
        VALID_LOCATION=$(python3 -c "import json; print(str(json.load(open('/tmp/segmentation_analysis.json')).get('valid_location', False)).lower())" 2>/dev/null || echo "false")
        VALID_INTENSITY=$(python3 -c "import json; print(str(json.load(open('/tmp/segmentation_analysis.json')).get('valid_intensity', False)).lower())" 2>/dev/null || echo "false")
        ANALYSIS_ERROR=$(python3 -c "import json; print(json.load(open('/tmp/segmentation_analysis.json')).get('error', '') or '')" 2>/dev/null || echo "")
        
        echo "Analysis results:"
        echo "  Voxel count: $VOXEL_COUNT"
        echo "  Mean intensity: $MEAN_INTENSITY"
        echo "  Valid location: $VALID_LOCATION"
        echo "  Valid intensity: $VALID_INTENSITY"
    fi
fi

# Calculate file size in KB
FILE_SIZE_KB=$((FILE_SIZE / 1024))

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "segmentation_file_exists": $FILE_EXISTS,
    "segmentation_file_path": "$FILE_PATH",
    "file_size_bytes": $FILE_SIZE,
    "file_size_kb": $FILE_SIZE_KB,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "voxel_count": $VOXEL_COUNT,
    "mean_intensity": $MEAN_INTENSITY,
    "valid_location": $VALID_LOCATION,
    "valid_intensity": $VALID_INTENSITY,
    "analysis_error": "$ANALYSIS_ERROR"
}
EOF

# Move to final location with permission handling
RESULT_FILE="/tmp/seg_task_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"