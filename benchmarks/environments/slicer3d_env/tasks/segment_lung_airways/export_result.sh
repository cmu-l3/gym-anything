#!/bin/bash
echo "=== Exporting Segment Lung Airways Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

export DISPLAY=:1

# ============================================================
# Capture final state
# ============================================================
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# ============================================================
# Get timestamps
# ============================================================
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ============================================================
# Check Slicer status
# ============================================================
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
fi

# ============================================================
# Check for segmentation file
# ============================================================
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
SEG_FILE="$EXPORT_DIR/airways_segmentation.seg.nrrd"

SEG_EXISTS="false"
SEG_SIZE=0
SEG_MODIFIED=0
FILE_CREATED_DURING_TASK="false"

# Also check for alternative file names/locations
SEARCH_PATHS=(
    "$SEG_FILE"
    "$EXPORT_DIR/airways.seg.nrrd"
    "$EXPORT_DIR/Airways.seg.nrrd"
    "$EXPORT_DIR/airway_segmentation.seg.nrrd"
    "/home/ga/Documents/SlicerData/LIDC/airways_segmentation.seg.nrrd"
    "/home/ga/airways_segmentation.seg.nrrd"
)

FOUND_SEG_FILE=""
for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FOUND_SEG_FILE="$path"
        echo "Found segmentation at: $path"
        break
    fi
done

if [ -n "$FOUND_SEG_FILE" ]; then
    SEG_EXISTS="true"
    SEG_SIZE=$(stat -c%s "$FOUND_SEG_FILE" 2>/dev/null || echo "0")
    SEG_MODIFIED=$(stat -c%Y "$FOUND_SEG_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created after task started
    if [ "$SEG_MODIFIED" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created during task session"
    else
        echo "WARNING: File timestamp ($SEG_MODIFIED) predates task start ($TASK_START)"
    fi
    
    # Copy to expected location if found elsewhere
    if [ "$FOUND_SEG_FILE" != "$SEG_FILE" ]; then
        cp "$FOUND_SEG_FILE" "$SEG_FILE" 2>/dev/null || true
    fi
fi

# ============================================================
# Analyze segmentation if it exists
# ============================================================
ANALYSIS_SUCCESS="false"
VOLUME_ML=0
NUM_COMPONENTS=0
IS_CENTRAL="false"
CENTROID_X=0
CENTROID_Y=0
CENTROID_Z=0
IMAGE_SHAPE=""
MEAN_HU=-1000

if [ "$SEG_EXISTS" = "true" ] && [ -f "$FOUND_SEG_FILE" ]; then
    echo "Analyzing segmentation..."
    
    python3 << 'PYEOF' > /tmp/seg_analysis_output.json 2>&1
import json
import os
import sys

seg_file = None
for path in [
    "/home/ga/Documents/SlicerData/Exports/airways_segmentation.seg.nrrd",
    "/home/ga/Documents/SlicerData/Exports/airways.seg.nrrd",
    "/home/ga/Documents/SlicerData/LIDC/airways_segmentation.seg.nrrd"
]:
    if os.path.exists(path):
        seg_file = path
        break

if not seg_file:
    print(json.dumps({"error": "Segmentation file not found", "success": False}))
    sys.exit(1)

try:
    import numpy as np
except ImportError:
    print(json.dumps({"error": "numpy not available", "success": False}))
    sys.exit(1)

# Try to load NRRD file
try:
    import nrrd
except ImportError:
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pynrrd"], 
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import nrrd
    except:
        # Try nibabel as fallback
        try:
            import nibabel as nib
            img = nib.load(seg_file)
            data = img.get_fdata()
            spacing = img.header.get_zooms()[:3] if hasattr(img.header, 'get_zooms') else [1,1,1]
        except:
            print(json.dumps({"error": "Cannot load NRRD/NIfTI file", "success": False}))
            sys.exit(1)

try:
    # Load with nrrd
    data, header = nrrd.read(seg_file)
    
    # Get spacing from header
    spacing = [1.0, 1.0, 1.0]
    if 'space directions' in header:
        space_dirs = header['space directions']
        spacing = []
        for d in space_dirs:
            if d is not None and hasattr(d, '__iter__'):
                spacing.append(float(np.linalg.norm(d)))
            else:
                spacing.append(1.0)
    elif 'spacings' in header:
        spacing = [float(s) for s in header['spacings']]
    
    while len(spacing) < 3:
        spacing.append(1.0)
    
except Exception as e:
    print(json.dumps({"error": f"Failed to load: {str(e)}", "success": False}))
    sys.exit(1)

# Analyze the segmentation
try:
    binary_mask = (data > 0).astype(np.uint8)
    
    # Calculate volume
    voxel_count = int(np.sum(binary_mask))
    voxel_volume_mm3 = float(spacing[0] * spacing[1] * spacing[2])
    volume_mm3 = voxel_count * voxel_volume_mm3
    volume_ml = volume_mm3 / 1000.0
    
    # Calculate centroid
    if voxel_count > 0:
        indices = np.argwhere(binary_mask)
        centroid_voxels = np.mean(indices, axis=0)
        centroid_mm = [float(c * s) for c, s in zip(centroid_voxels, spacing)]
    else:
        centroid_voxels = [0, 0, 0]
        centroid_mm = [0, 0, 0]
    
    # Count connected components
    try:
        from scipy.ndimage import label as scipy_label
        labeled, num_components = scipy_label(binary_mask)
    except ImportError:
        num_components = 1  # Assume single component if scipy unavailable
    
    # Check if centroid is central (not at image edge)
    image_center = np.array(data.shape) / 2.0
    if voxel_count > 0:
        centroid_offset = np.abs(np.array(centroid_voxels) - image_center)
        is_central = all(offset < dim * 0.4 for offset, dim in zip(centroid_offset, data.shape))
    else:
        is_central = False
    
    result = {
        "success": True,
        "volume_ml": round(float(volume_ml), 2),
        "voxel_count": voxel_count,
        "num_components": int(num_components),
        "centroid_voxels": [float(c) for c in centroid_voxels] if voxel_count > 0 else [0, 0, 0],
        "centroid_mm": centroid_mm,
        "is_central": bool(is_central),
        "image_shape": list(data.shape),
        "spacing_mm": [float(s) for s in spacing],
        "file_path": seg_file
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": f"Analysis failed: {str(e)}", "success": False}))
    sys.exit(1)
PYEOF

    # Parse analysis results
    if [ -f /tmp/seg_analysis_output.json ]; then
        ANALYSIS_JSON=$(cat /tmp/seg_analysis_output.json)
        
        # Check if analysis was successful
        ANALYSIS_SUCCESS=$(echo "$ANALYSIS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('success', False) else 'false')" 2>/dev/null || echo "false")
        
        if [ "$ANALYSIS_SUCCESS" = "true" ]; then
            VOLUME_ML=$(echo "$ANALYSIS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('volume_ml', 0))" 2>/dev/null || echo "0")
            NUM_COMPONENTS=$(echo "$ANALYSIS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('num_components', 0))" 2>/dev/null || echo "0")
            IS_CENTRAL=$(echo "$ANALYSIS_JSON" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('is_central', False) else 'false')" 2>/dev/null || echo "false")
            IMAGE_SHAPE=$(echo "$ANALYSIS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('image_shape', []))" 2>/dev/null || echo "[]")
            
            echo "Analysis results:"
            echo "  Volume: ${VOLUME_ML} mL"
            echo "  Components: ${NUM_COMPONENTS}"
            echo "  Is central: ${IS_CENTRAL}"
        else
            echo "Analysis failed or returned error"
            cat /tmp/seg_analysis_output.json
        fi
    fi
fi

# ============================================================
# Check windows for evidence of work
# ============================================================
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Current windows: $WINDOWS_LIST"

SEGMENT_EDITOR_USED="false"
SHOW_3D_VISIBLE="false"

if echo "$WINDOWS_LIST" | grep -qi "segment"; then
    SEGMENT_EDITOR_USED="true"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_id": "segment_lung_airways",
    "version": "1",
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "slicer_running": $SLICER_RUNNING,
    "segmentation_exists": $SEG_EXISTS,
    "segmentation_file": "$FOUND_SEG_FILE",
    "expected_file": "$SEG_FILE",
    "file_size_bytes": $SEG_SIZE,
    "file_modified_timestamp": $SEG_MODIFIED,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis_success": $ANALYSIS_SUCCESS,
    "volume_ml": $VOLUME_ML,
    "num_components": $NUM_COMPONENTS,
    "is_central": $IS_CENTRAL,
    "image_shape": "$IMAGE_SHAPE",
    "segment_editor_used": $SEGMENT_EDITOR_USED,
    "screenshot_final": "/tmp/task_final_state.png",
    "screenshot_initial": "/tmp/task_initial_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results Summary ==="
echo "Segmentation exists: $SEG_EXISTS"
echo "File created during task: $FILE_CREATED_DURING_TASK"
echo "Volume: ${VOLUME_ML} mL"
echo "Components: $NUM_COMPONENTS"
echo "Centroid central: $IS_CENTRAL"
echo ""
echo "Result saved to: /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="