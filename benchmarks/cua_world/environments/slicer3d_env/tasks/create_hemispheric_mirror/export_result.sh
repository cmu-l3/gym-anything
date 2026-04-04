#!/bin/bash
echo "=== Exporting Create Hemispheric Mirror Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Paths
OUTPUT_FILE="/home/ga/Documents/SlicerData/Exports/MRHead_mirrored.nrrd"
SAMPLE_FILE="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"

# Check if output file exists
OUTPUT_EXISTS="false"
OUTPUT_SIZE_BYTES="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE_BYTES=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file was created during task"
    else
        echo "WARNING: Output file exists but was NOT created during task"
    fi
    
    echo "Output file: $OUTPUT_FILE"
    echo "  Size: $OUTPUT_SIZE_BYTES bytes"
    echo "  Modified: $(date -d @$OUTPUT_MTIME)"
else
    echo "Output file NOT found at $OUTPUT_FILE"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
fi

# Get window list for evidence
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Windows: $WINDOWS_LIST"

# Check for transform evidence in windows
TRANSFORM_WINDOW_VISIBLE="false"
if echo "$WINDOWS_LIST" | grep -qi "Transform"; then
    TRANSFORM_WINDOW_VISIBLE="true"
    echo "Transforms module was accessed"
fi

# Analyze the output file if it exists
FLIP_DETECTED="false"
FLIP_AXIS=""
VOXELS_MATCH="false"
DIRECTION_INVERTED="false"

if [ "$OUTPUT_EXISTS" = "true" ] && [ "$OUTPUT_SIZE_BYTES" -gt 1000000 ]; then
    echo "Analyzing mirrored volume..."
    
    python3 << 'PYEOF'
import json
import os
import sys

try:
    import nibabel as nib
    import numpy as np
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "numpy"])
    import nibabel as nib
    import numpy as np

output_file = "/home/ga/Documents/SlicerData/Exports/MRHead_mirrored.nrrd"
sample_file = "/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
original_props_file = "/tmp/original_volume_props.json"

results = {
    "flip_detected": False,
    "flip_axis": "",
    "voxels_match": False,
    "direction_inverted": False,
    "analysis_error": None
}

try:
    # Load original properties
    original_props = {}
    if os.path.exists(original_props_file):
        with open(original_props_file) as f:
            original_props = json.load(f)
    
    # Load both volumes
    orig_img = nib.load(sample_file)
    mir_img = nib.load(output_file)
    
    orig_data = orig_img.get_fdata()
    mir_data = mir_img.get_fdata()
    
    orig_affine = orig_img.affine
    mir_affine = mir_img.affine
    
    # Extract direction matrices
    orig_dir = orig_affine[:3, :3]
    mir_dir = mir_affine[:3, :3]
    
    print(f"Original shape: {orig_data.shape}")
    print(f"Mirrored shape: {mir_data.shape}")
    print(f"Original direction diagonal: [{orig_dir[0,0]:.3f}, {orig_dir[1,1]:.3f}, {orig_dir[2,2]:.3f}]")
    print(f"Mirrored direction diagonal: [{mir_dir[0,0]:.3f}, {mir_dir[1,1]:.3f}, {mir_dir[2,2]:.3f}]")
    
    # Check for axis inversion in direction matrix
    # L-R flip: first column should be negated
    # A-P flip: second column should be negated
    # S-I flip: third column should be negated
    
    lr_inverted = np.allclose(orig_dir[:, 0], -mir_dir[:, 0], rtol=0.1)
    ap_inverted = np.allclose(orig_dir[:, 1], -mir_dir[:, 1], rtol=0.1)
    si_inverted = np.allclose(orig_dir[:, 2], -mir_dir[:, 2], rtol=0.1)
    
    # Also check diagonal elements for simpler transforms
    lr_diag_inv = np.sign(orig_dir[0,0]) != np.sign(mir_dir[0,0])
    ap_diag_inv = np.sign(orig_dir[1,1]) != np.sign(mir_dir[1,1])
    si_diag_inv = np.sign(orig_dir[2,2]) != np.sign(mir_dir[2,2])
    
    if lr_inverted or lr_diag_inv:
        results["flip_axis"] = "LR"
        results["direction_inverted"] = True
        print("L-R flip detected in direction matrix")
    elif ap_inverted or ap_diag_inv:
        results["flip_axis"] = "AP"
        results["direction_inverted"] = True
        print("A-P flip detected in direction matrix")
    elif si_inverted or si_diag_inv:
        results["flip_axis"] = "SI"
        results["direction_inverted"] = True
        print("S-I flip detected in direction matrix")
    
    # Verify voxel data is actually flipped
    # For L-R flip: orig[x,y,z] should equal mir[nx-x-1, y, z]
    if orig_data.shape == mir_data.shape:
        nx, ny, nz = orig_data.shape
        
        # Sample several points to verify flip
        test_points = [
            (nx//4, ny//2, nz//2),
            (nx//2, ny//3, nz//2),
            (3*nx//4, ny//2, nz//3),
            (nx//3, 2*ny//3, nz//2),
        ]
        
        lr_matches = 0
        ap_matches = 0
        si_matches = 0
        
        for x, y, z in test_points:
            orig_val = orig_data[x, y, z]
            
            # Check L-R flip
            mir_x = nx - x - 1
            if 0 <= mir_x < nx:
                mir_val_lr = mir_data[mir_x, y, z]
                if np.isclose(orig_val, mir_val_lr, rtol=0.05):
                    lr_matches += 1
            
            # Check A-P flip
            mir_y = ny - y - 1
            if 0 <= mir_y < ny:
                mir_val_ap = mir_data[x, mir_y, z]
                if np.isclose(orig_val, mir_val_ap, rtol=0.05):
                    ap_matches += 1
            
            # Check S-I flip
            mir_z = nz - z - 1
            if 0 <= mir_z < nz:
                mir_val_si = mir_data[x, y, mir_z]
                if np.isclose(orig_val, mir_val_si, rtol=0.05):
                    si_matches += 1
        
        total_points = len(test_points)
        print(f"Voxel verification - LR: {lr_matches}/{total_points}, AP: {ap_matches}/{total_points}, SI: {si_matches}/{total_points}")
        
        # Determine flip type from voxel data
        if lr_matches >= total_points * 0.75:
            results["voxels_match"] = True
            if not results["flip_axis"]:
                results["flip_axis"] = "LR"
            results["flip_detected"] = True
            print("L-R flip verified in voxel data")
        elif ap_matches >= total_points * 0.75:
            results["voxels_match"] = True
            if not results["flip_axis"]:
                results["flip_axis"] = "AP"
            results["flip_detected"] = True
            print("A-P flip verified in voxel data")
        elif si_matches >= total_points * 0.75:
            results["voxels_match"] = True
            if not results["flip_axis"]:
                results["flip_axis"] = "SI"
            results["flip_detected"] = True
            print("S-I flip verified in voxel data")
        
        # Even if direction wasn't inverted, check if raw data is flipped
        if not results["flip_detected"]:
            # Maybe transform was hardened and data physically flipped
            # Compare correlation of flipped versions
            lr_corr = np.corrcoef(orig_data.flatten()[:10000], 
                                   np.flip(mir_data, axis=0).flatten()[:10000])[0,1]
            print(f"L-R flip correlation: {lr_corr:.4f}")
            if lr_corr > 0.95:
                results["flip_detected"] = True
                results["flip_axis"] = "LR"
                results["voxels_match"] = True
    else:
        print(f"Shape mismatch: original {orig_data.shape} vs mirrored {mir_data.shape}")
        results["analysis_error"] = "Shape mismatch"
    
    # Store additional metrics
    results["original_shape"] = list(orig_data.shape)
    results["mirrored_shape"] = list(mir_data.shape)
    results["orig_direction"] = orig_dir.tolist()
    results["mir_direction"] = mir_dir.tolist()

except Exception as e:
    print(f"Analysis error: {e}")
    results["analysis_error"] = str(e)

# Save results
with open("/tmp/mirror_analysis.json", "w") as f:
    json.dump(results, f, indent=2)

print(f"\nAnalysis results saved to /tmp/mirror_analysis.json")
PYEOF
    
    # Read analysis results
    if [ -f /tmp/mirror_analysis.json ]; then
        FLIP_DETECTED=$(python3 -c "import json; print('true' if json.load(open('/tmp/mirror_analysis.json')).get('flip_detected', False) else 'false')")
        FLIP_AXIS=$(python3 -c "import json; print(json.load(open('/tmp/mirror_analysis.json')).get('flip_axis', ''))")
        VOXELS_MATCH=$(python3 -c "import json; print('true' if json.load(open('/tmp/mirror_analysis.json')).get('voxels_match', False) else 'false')")
        DIRECTION_INVERTED=$(python3 -c "import json; print('true' if json.load(open('/tmp/mirror_analysis.json')).get('direction_inverted', False) else 'false')")
    fi
fi

# Try to get scene info from Slicer if running
NUM_VOLUMES=0
NUM_TRANSFORMS=0

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer scene state..."
    
    # Create Python script to query scene
    cat > /tmp/query_scene.py << 'PYEOF'
import json
try:
    import slicer
    
    # Count volumes
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    num_volumes = len(volume_nodes)
    
    # Count transforms
    transform_nodes = slicer.util.getNodesByClass("vtkMRMLLinearTransformNode")
    num_transforms = len(transform_nodes)
    
    # Get volume names
    volume_names = [node.GetName() for node in volume_nodes]
    
    scene_info = {
        "num_volumes": num_volumes,
        "num_transforms": num_transforms,
        "volume_names": volume_names
    }
    
    with open("/tmp/scene_info.json", "w") as f:
        json.dump(scene_info, f)
    
    print(f"Volumes: {num_volumes}, Transforms: {num_transforms}")
    print(f"Volume names: {volume_names}")
    
except Exception as e:
    print(f"Error querying scene: {e}")
    with open("/tmp/scene_info.json", "w") as f:
        json.dump({"error": str(e)}, f)
PYEOF
    
    # Run query (may not work if Slicer is busy)
    timeout 10 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/query_scene.py > /tmp/scene_query.log 2>&1 || true
    
    if [ -f /tmp/scene_info.json ]; then
        NUM_VOLUMES=$(python3 -c "import json; print(json.load(open('/tmp/scene_info.json')).get('num_volumes', 0))" 2>/dev/null || echo "0")
        NUM_TRANSFORMS=$(python3 -c "import json; print(json.load(open('/tmp/scene_info.json')).get('num_transforms', 0))" 2>/dev/null || echo "0")
    fi
fi

# Create final result JSON
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE_BYTES,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "slicer_was_running": $SLICER_RUNNING,
    "transform_window_visible": $TRANSFORM_WINDOW_VISIBLE,
    "flip_detected": $FLIP_DETECTED,
    "flip_axis": "$FLIP_AXIS",
    "voxels_match": $VOXELS_MATCH,
    "direction_inverted": $DIRECTION_INVERTED,
    "num_volumes_in_scene": $NUM_VOLUMES,
    "num_transforms_in_scene": $NUM_TRANSFORMS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/mirror_task_result.json 2>/dev/null || sudo rm -f /tmp/mirror_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mirror_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mirror_task_result.json
chmod 666 /tmp/mirror_task_result.json 2>/dev/null || sudo chmod 666 /tmp/mirror_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/mirror_task_result.json
echo ""
echo "=== Export Complete ==="