#!/bin/bash
echo "=== Exporting Crop Volume ROI Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot immediately
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/crop_final.png 2>/dev/null || true
sleep 1

# Get task timing info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get initial state
INITIAL_OUTPUT_EXISTS="false"
INITIAL_OUTPUT_MTIME="0"
if [ -f /tmp/crop_initial_state.json ]; then
    INITIAL_OUTPUT_EXISTS=$(python3 -c "import json; print(str(json.load(open('/tmp/crop_initial_state.json')).get('initial_output_exists', False)).lower())" 2>/dev/null || echo "false")
    INITIAL_OUTPUT_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/crop_initial_state.json')).get('initial_output_mtime', 0))" 2>/dev/null || echo "0")
fi

# Get original volume info
ORIGINAL_DIMS="[256, 256, 130]"
ORIGINAL_VOXELS="8519680"
if [ -f /tmp/original_volume_info.json ]; then
    ORIGINAL_DIMS=$(python3 -c "import json; print(json.load(open('/tmp/original_volume_info.json')).get('original_dimensions', [256, 256, 130]))" 2>/dev/null || echo "[256, 256, 130]")
    ORIGINAL_VOXELS=$(python3 -c "import json; print(json.load(open('/tmp/original_volume_info.json')).get('original_voxel_count', 8519680))" 2>/dev/null || echo "8519680")
fi

# Check output file
OUTPUT_PATH="/home/ga/Documents/SlicerData/Exports/MRHead_cropped.nrrd"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created or modified during task
    if [ "$INITIAL_OUTPUT_EXISTS" = "false" ]; then
        if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    else
        if [ "$OUTPUT_MTIME" -gt "$INITIAL_OUTPUT_MTIME" ]; then
            FILE_MODIFIED_DURING_TASK="true"
        fi
    fi
fi

# Analyze cropped volume dimensions
CROPPED_DIMS="[]"
CROPPED_VOXELS="0"
DIMS_SMALLER="false"
BRAIN_PRESERVED="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Analyzing cropped volume..."
    python3 << 'PYEOF'
import json
import os

output_path = "/home/ga/Documents/SlicerData/Exports/MRHead_cropped.nrrd"
result = {
    "cropped_dimensions": [],
    "cropped_voxel_count": 0,
    "analysis_error": None
}

try:
    # Try nibabel first
    import nibabel as nib
    nii = nib.load(output_path)
    dims = list(nii.shape)
    result["cropped_dimensions"] = dims[:3] if len(dims) >= 3 else dims
    result["cropped_voxel_count"] = int(dims[0] * dims[1] * dims[2]) if len(dims) >= 3 else 0
except ImportError:
    try:
        # Try nrrd library
        import nrrd
        data, header = nrrd.read(output_path)
        dims = list(data.shape)
        result["cropped_dimensions"] = dims[:3] if len(dims) >= 3 else dims
        result["cropped_voxel_count"] = int(dims[0] * dims[1] * dims[2]) if len(dims) >= 3 else 0
    except Exception as e:
        result["analysis_error"] = str(e)
except Exception as e:
    result["analysis_error"] = str(e)

with open("/tmp/cropped_volume_info.json", "w") as f:
    json.dump(result, f)

print(f"Cropped dimensions: {result['cropped_dimensions']}")
print(f"Cropped voxel count: {result['cropped_voxel_count']}")
PYEOF

    # Read analysis results
    if [ -f /tmp/cropped_volume_info.json ]; then
        CROPPED_DIMS=$(python3 -c "import json; print(json.load(open('/tmp/cropped_volume_info.json')).get('cropped_dimensions', []))" 2>/dev/null || echo "[]")
        CROPPED_VOXELS=$(python3 -c "import json; print(json.load(open('/tmp/cropped_volume_info.json')).get('cropped_voxel_count', 0))" 2>/dev/null || echo "0")
        
        # Check if dimensions are smaller
        DIMS_SMALLER=$(python3 << PYCHECK
import json
try:
    orig = json.load(open('/tmp/original_volume_info.json')).get('original_dimensions', [256, 256, 130])
    crop = json.load(open('/tmp/cropped_volume_info.json')).get('cropped_dimensions', [])
    if len(orig) >= 3 and len(crop) >= 3:
        # At least one dimension must be smaller
        smaller = any(crop[i] < orig[i] for i in range(3))
        print("true" if smaller else "false")
    else:
        print("false")
except Exception as e:
    print("false")
PYCHECK
)
        
        # Check if brain is preserved (not over-cropped)
        BRAIN_PRESERVED=$(python3 << PYCHECK
import json
try:
    crop = json.load(open('/tmp/cropped_volume_info.json')).get('cropped_dimensions', [])
    if len(crop) >= 3:
        # Each dimension should be > 50 voxels (reasonable brain size)
        preserved = all(d > 50 for d in crop[:3])
        print("true" if preserved else "false")
    else:
        print("false")
except Exception as e:
    print("false")
PYCHECK
)
    fi
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check if original volume still exists in scene (via Slicer API)
ORIGINAL_PRESERVED="false"
CROPPED_IN_SCENE="false"
NUM_VOLUMES="0"

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer scene state..."
    cat > /tmp/check_scene.py << 'SCENEPY'
import slicer
import json

result = {
    "num_volume_nodes": 0,
    "volume_names": [],
    "has_original": False,
    "has_cropped": False,
    "roi_exists": False
}

# Count volume nodes
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
result["num_volume_nodes"] = volume_nodes.GetNumberOfItems()

for i in range(volume_nodes.GetNumberOfItems()):
    node = volume_nodes.GetItemAsObject(i)
    name = node.GetName().lower()
    result["volume_names"].append(node.GetName())
    if "mrhead" in name and "crop" not in name:
        result["has_original"] = True
    if "crop" in name:
        result["has_cropped"] = True

# Check for ROI
roi_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsROINode")
if roi_nodes.GetNumberOfItems() > 0:
    result["roi_exists"] = True

with open("/tmp/scene_state.json", "w") as f:
    json.dump(result, f)

print(f"Volumes: {result['num_volume_nodes']}, Original: {result['has_original']}, Cropped: {result['has_cropped']}")
SCENEPY

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/check_scene.py --no-main-window > /tmp/scene_check.log 2>&1 &
    SCENE_PID=$!
    sleep 8
    kill $SCENE_PID 2>/dev/null || true
    
    if [ -f /tmp/scene_state.json ]; then
        NUM_VOLUMES=$(python3 -c "import json; print(json.load(open('/tmp/scene_state.json')).get('num_volume_nodes', 0))" 2>/dev/null || echo "0")
        ORIGINAL_PRESERVED=$(python3 -c "import json; print(str(json.load(open('/tmp/scene_state.json')).get('has_original', False)).lower())" 2>/dev/null || echo "false")
        CROPPED_IN_SCENE=$(python3 -c "import json; print(str(json.load(open('/tmp/scene_state.json')).get('has_cropped', False)).lower())" 2>/dev/null || echo "false")
    fi
fi

# If we couldn't query Slicer, assume original is preserved if output is different
if [ "$ORIGINAL_PRESERVED" = "false" ] && [ "$OUTPUT_EXISTS" = "true" ] && [ "$DIMS_SMALLER" = "true" ]; then
    ORIGINAL_PRESERVED="true"
fi

# Check for any .nrrd files in exports directory
EXPORT_FILES=$(ls -1 /home/ga/Documents/SlicerData/Exports/*.nrrd 2>/dev/null | wc -l)

# Get window list for VLM evidence
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
CROP_MODULE_VISIBLE="false"
if echo "$WINDOWS_LIST" | grep -qi "Crop"; then
    CROP_MODULE_VISIBLE="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "original_dimensions": $ORIGINAL_DIMS,
    "original_voxel_count": $ORIGINAL_VOXELS,
    "cropped_dimensions": $CROPPED_DIMS,
    "cropped_voxel_count": $CROPPED_VOXELS,
    "dimensions_smaller": $DIMS_SMALLER,
    "brain_preserved": $BRAIN_PRESERVED,
    "original_preserved": $ORIGINAL_PRESERVED,
    "cropped_in_scene": $CROPPED_IN_SCENE,
    "num_volumes_in_scene": $NUM_VOLUMES,
    "slicer_was_running": $SLICER_RUNNING,
    "export_files_count": $EXPORT_FILES,
    "crop_module_visible": $CROP_MODULE_VISIBLE,
    "screenshot_path": "/tmp/crop_final.png"
}
EOF

# Move to final location
rm -f /tmp/crop_task_result.json 2>/dev/null || sudo rm -f /tmp/crop_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/crop_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/crop_task_result.json
chmod 666 /tmp/crop_task_result.json 2>/dev/null || sudo chmod 666 /tmp/crop_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/crop_task_result.json
echo ""
echo "=== Export Complete ==="