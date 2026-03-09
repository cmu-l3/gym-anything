#!/bin/bash
echo "=== Exporting Create Masked Brain Volume Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Define paths
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_PATH="$EXPORT_DIR/MRHead_brain_only.nrrd"
SAMPLE_FILE="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    echo "Final screenshot saved"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
fi

# Check for output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo "Output file found: $OUTPUT_PATH"
    echo "  Size: $(($OUTPUT_SIZE / 1024)) KB"
    echo "  Modified: $(date -d @$OUTPUT_MTIME 2>/dev/null || echo 'unknown')"
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "  File was created during task execution"
    else
        echo "  WARNING: File may have existed before task"
    fi
else
    echo "Output file NOT found at: $OUTPUT_PATH"
    
    # Search for any .nrrd files that might be the output
    echo "Searching for potential output files..."
    find /home/ga -name "*.nrrd" -newer /tmp/task_start_time.txt 2>/dev/null | head -5
fi

# Also search for alternative output locations
ALT_OUTPUT_PATHS=(
    "$EXPORT_DIR/MRHead_brain_only.nii.gz"
    "$EXPORT_DIR/MRHead_brain_only.nii"
    "$EXPORT_DIR/MRHead-brain-only.nrrd"
    "$EXPORT_DIR/brain_only.nrrd"
    "/home/ga/MRHead_brain_only.nrrd"
    "/home/ga/Documents/MRHead_brain_only.nrrd"
)

ALT_OUTPUT_FOUND=""
for alt_path in "${ALT_OUTPUT_PATHS[@]}"; do
    if [ -f "$alt_path" ]; then
        ALT_OUTPUT_FOUND="$alt_path"
        echo "Found alternative output at: $alt_path"
        break
    fi
done

# Analyze the output volume if it exists
ANALYSIS_JSON="{}"
ANALYZE_PATH="$OUTPUT_PATH"
if [ "$OUTPUT_EXISTS" = "false" ] && [ -n "$ALT_OUTPUT_FOUND" ]; then
    ANALYZE_PATH="$ALT_OUTPUT_FOUND"
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$ANALYZE_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$ANALYZE_PATH" 2>/dev/null || echo "0")
fi

if [ "$OUTPUT_EXISTS" = "true" ] && [ -f "$ANALYZE_PATH" ]; then
    echo ""
    echo "Analyzing output volume: $ANALYZE_PATH"
    
    ANALYSIS_JSON=$(python3 << PYEOF
import json
import sys
import os

try:
    import numpy as np
except ImportError:
    print('{"error": "numpy not available"}')
    sys.exit(0)

analyze_path = "$ANALYZE_PATH"
sample_path = "$SAMPLE_FILE"

# Try to load with nrrd first, then nibabel
data = None
header = None

try:
    import nrrd
    data, header = nrrd.read(analyze_path)
    print(f"Loaded with nrrd: shape={data.shape}", file=sys.stderr)
except ImportError:
    try:
        import nibabel as nib
        img = nib.load(analyze_path)
        data = img.get_fdata()
        print(f"Loaded with nibabel: shape={data.shape}", file=sys.stderr)
    except ImportError:
        print('{"error": "Neither nrrd nor nibabel available"}')
        sys.exit(0)
    except Exception as e:
        print(json.dumps({"error": f"nibabel load failed: {str(e)}"}))
        sys.exit(0)
except Exception as e:
    try:
        import nibabel as nib
        img = nib.load(analyze_path)
        data = img.get_fdata()
        print(f"Loaded with nibabel fallback: shape={data.shape}", file=sys.stderr)
    except Exception as e2:
        print(json.dumps({"error": f"All loaders failed: {str(e)}, {str(e2)}"}))
        sys.exit(0)

if data is None:
    print('{"error": "Could not load volume data"}')
    sys.exit(0)

# Analyze the volume
shape = list(data.shape)
total_voxels = int(data.size)

# Count near-zero voxels (threshold of 5 for noise tolerance)
near_zero_count = int(np.sum(np.abs(data) < 5))
near_zero_pct = float(near_zero_count) / total_voxels * 100

# Check if dimensions match expected (256x256x130 in any order)
expected_dims = [256, 256, 130]
shape_sorted = sorted(shape)
expected_sorted = sorted(expected_dims)
shape_matches = (shape_sorted == expected_sorted) or (len(shape) == 3 and all(100 <= s <= 300 for s in shape))

# Analyze central region (brain area should be preserved)
if len(shape) == 3:
    cx = shape[0] // 4
    cy = shape[1] // 4
    cz = shape[2] // 4
    center_region = data[cx:3*cx, cy:3*cy, cz:3*cz]
    center_mean = float(np.mean(center_region))
    center_nonzero = int(np.sum(center_region > 5))
    center_nonzero_pct = float(center_nonzero) / center_region.size * 100
else:
    center_mean = float(np.mean(data))
    center_nonzero_pct = 50.0

# Determine if masking was effective
effective_masking = near_zero_pct > 30  # At least 30% should be masked out

# Determine if brain signal is preserved
brain_preserved = center_nonzero_pct > 50 and center_mean > 20

# Compare to input file if available
input_comparison = {}
try:
    if os.path.exists(sample_path):
        try:
            import nrrd
            input_data, _ = nrrd.read(sample_path)
        except:
            import nibabel as nib
            input_img = nib.load(sample_path)
            input_data = input_img.get_fdata()
        
        input_near_zero = int(np.sum(np.abs(input_data) < 5))
        input_near_zero_pct = float(input_near_zero) / input_data.size * 100
        
        input_comparison = {
            "input_near_zero_pct": round(input_near_zero_pct, 2),
            "masking_increased_zeros": near_zero_pct > input_near_zero_pct + 20
        }
except Exception as e:
    input_comparison = {"comparison_error": str(e)}

result = {
    "shape": shape,
    "expected_shape": expected_dims,
    "shape_matches": shape_matches,
    "total_voxels": total_voxels,
    "near_zero_count": near_zero_count,
    "near_zero_percentage": round(near_zero_pct, 2),
    "effective_masking": effective_masking,
    "center_mean": round(center_mean, 2),
    "center_nonzero_pct": round(center_nonzero_pct, 2),
    "brain_preserved": brain_preserved,
    "min_value": float(np.min(data)),
    "max_value": float(np.max(data)),
    "mean_value": round(float(np.mean(data)), 2),
    "input_comparison": input_comparison
}

print(json.dumps(result))
PYEOF
)
    echo "Volume analysis complete"
    echo "$ANALYSIS_JSON" | python3 -m json.tool 2>/dev/null || echo "$ANALYSIS_JSON"
fi

# Check for segmentation nodes (evidence of using Segment Editor)
SEGMENTATION_FOUND="false"
if [ "$SLICER_RUNNING" = "true" ]; then
    # Try to query Slicer for segmentation nodes
    cat > /tmp/check_scene.py << 'PYEOF'
import json
try:
    import slicer
    
    # Check for segmentation nodes
    seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    
    result = {
        "segmentation_count": len(seg_nodes),
        "volume_count": len(vol_nodes),
        "segmentation_names": [n.GetName() for n in seg_nodes],
        "volume_names": [n.GetName() for n in vol_nodes]
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

    SCENE_INFO=$(sudo -u ga DISPLAY=:1 timeout 10 /opt/Slicer/Slicer --no-main-window --python-script /tmp/check_scene.py 2>/dev/null || echo '{}')
    if echo "$SCENE_INFO" | grep -q "segmentation_count"; then
        SEG_COUNT=$(echo "$SCENE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('segmentation_count', 0))" 2>/dev/null || echo "0")
        if [ "$SEG_COUNT" -gt 0 ]; then
            SEGMENTATION_FOUND="true"
            echo "Segmentation nodes found in scene: $SEG_COUNT"
        fi
    fi
fi

# Build final result JSON
RESULT_FILE="/tmp/task_result.json"
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_name": "create_masked_brain_volume",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$ANALYZE_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_modified_timestamp": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "segmentation_found": $SEGMENTATION_FOUND,
    "volume_analysis": $ANALYSIS_JSON,
    "alternative_output_found": "$ALT_OUTPUT_FOUND",
    "sample_file_exists": $([ -f "$SAMPLE_FILE" ] && echo "true" || echo "false"),
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final_state.png"
    }
}
EOF

# Move to final location with proper permissions
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Results saved to: $RESULT_FILE"
echo ""
cat "$RESULT_FILE" | python3 -m json.tool 2>/dev/null || cat "$RESULT_FILE"