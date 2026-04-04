#!/bin/bash
echo "=== Exporting Intensity Masked Segmentation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_SEG="$EXPORTS_DIR/fat_segmentation.seg.nrrd"
OUTPUT_SEG_ALT="$EXPORTS_DIR/fat_segmentation.nii.gz"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
sleep 1

# Get CT file path
CT_FILE=$(cat /tmp/ct_file_path.txt 2>/dev/null || echo "$AMOS_DIR/amos_0001.nii.gz")
CASE_ID=$(cat /tmp/amos_case_id.txt 2>/dev/null || echo "amos_0001")

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Search for segmentation files
SEG_FILE=""
SEG_EXISTS="false"
SEG_SIZE=0
SEG_MTIME=0
FILE_CREATED_DURING_TASK="false"

# Check primary location
for check_path in "$OUTPUT_SEG" "$OUTPUT_SEG_ALT" "$EXPORTS_DIR"/*.seg.nrrd "$EXPORTS_DIR"/*segmentation*.nrrd "$EXPORTS_DIR"/*fat*.nrrd "$EXPORTS_DIR"/*fat*.nii.gz; do
    if [ -f "$check_path" ]; then
        SEG_EXISTS="true"
        SEG_FILE="$check_path"
        SEG_SIZE=$(stat -c %s "$check_path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$check_path" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        break
    fi
done

# Also check home directory and common save locations
if [ "$SEG_EXISTS" = "false" ]; then
    for check_path in /home/ga/*.seg.nrrd /home/ga/Desktop/*.seg.nrrd /home/ga/Documents/*.seg.nrrd; do
        if [ -f "$check_path" ]; then
            SEG_EXISTS="true"
            SEG_FILE="$check_path"
            SEG_SIZE=$(stat -c %s "$check_path" 2>/dev/null || echo "0")
            SEG_MTIME=$(stat -c %Y "$check_path" 2>/dev/null || echo "0")
            if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
                FILE_CREATED_DURING_TASK="true"
            fi
            echo "Found segmentation at alternate location: $check_path"
            break
        fi
    done
fi

echo "Segmentation file: $SEG_FILE"
echo "Exists: $SEG_EXISTS"
echo "Size: $SEG_SIZE bytes"
echo "Created during task: $FILE_CREATED_DURING_TASK"

# Analyze segmentation if it exists
VOXEL_COUNT=0
SEGMENT_NAME=""
INTENSITY_COMPLIANCE=0
CENTROID_X=0
CENTROID_Y=0
CENTROID_Z=0
ANALYSIS_SUCCESS="false"

if [ "$SEG_EXISTS" = "true" ] && [ -f "$SEG_FILE" ] && [ -f "$CT_FILE" ]; then
    echo "Analyzing segmentation intensity compliance..."
    
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

seg_file = "$SEG_FILE"
ct_file = "$CT_FILE"
output_json = "/tmp/seg_analysis.json"

intensity_min = -150
intensity_max = -50

result = {
    "analysis_success": False,
    "voxel_count": 0,
    "segment_name": "",
    "intensity_compliance": 0.0,
    "compliant_voxels": 0,
    "non_compliant_voxels": 0,
    "centroid": [0, 0, 0],
    "mean_intensity": 0,
    "std_intensity": 0,
    "min_intensity": 0,
    "max_intensity": 0,
    "error": ""
}

try:
    print(f"Loading segmentation: {seg_file}")
    
    # Handle different segmentation formats
    if seg_file.endswith('.seg.nrrd'):
        # Slicer segmentation format - may need special handling
        try:
            import nrrd
            seg_data, seg_header = nrrd.read(seg_file)
        except:
            # Try nibabel as fallback
            seg_nii = nib.load(seg_file)
            seg_data = seg_nii.get_fdata()
    else:
        seg_nii = nib.load(seg_file)
        seg_data = seg_nii.get_fdata()
    
    print(f"Segmentation shape: {seg_data.shape}")
    
    # Load CT volume
    print(f"Loading CT: {ct_file}")
    ct_nii = nib.load(ct_file)
    ct_data = ct_nii.get_fdata()
    print(f"CT shape: {ct_data.shape}")
    
    # Get binary mask (handle multi-label case)
    if seg_data.ndim == 4:
        # 4D segmentation (multiple segments)
        seg_mask = np.any(seg_data > 0, axis=-1)
    else:
        seg_mask = seg_data > 0
    
    # Ensure shapes match (may need to transpose or resample)
    if seg_mask.shape != ct_data.shape:
        print(f"WARNING: Shape mismatch - seg: {seg_mask.shape}, ct: {ct_data.shape}")
        # Try to match by taking min dimensions
        min_shape = tuple(min(s, c) for s, c in zip(seg_mask.shape[:3], ct_data.shape[:3]))
        seg_mask = seg_mask[:min_shape[0], :min_shape[1], :min_shape[2]]
        ct_data = ct_data[:min_shape[0], :min_shape[1], :min_shape[2]]
    
    voxel_count = int(np.sum(seg_mask))
    result["voxel_count"] = voxel_count
    print(f"Segmented voxel count: {voxel_count}")
    
    if voxel_count > 0:
        # Get intensities of segmented voxels
        seg_intensities = ct_data[seg_mask]
        
        # Calculate compliance
        compliant = (seg_intensities >= intensity_min) & (seg_intensities <= intensity_max)
        compliant_count = int(np.sum(compliant))
        non_compliant_count = voxel_count - compliant_count
        compliance_ratio = compliant_count / voxel_count
        
        result["compliant_voxels"] = compliant_count
        result["non_compliant_voxels"] = non_compliant_count
        result["intensity_compliance"] = float(compliance_ratio)
        
        # Intensity statistics
        result["mean_intensity"] = float(np.mean(seg_intensities))
        result["std_intensity"] = float(np.std(seg_intensities))
        result["min_intensity"] = float(np.min(seg_intensities))
        result["max_intensity"] = float(np.max(seg_intensities))
        
        print(f"Intensity compliance: {compliance_ratio*100:.1f}%")
        print(f"Compliant voxels: {compliant_count}, Non-compliant: {non_compliant_count}")
        print(f"Mean HU: {result['mean_intensity']:.1f}, Range: [{result['min_intensity']:.0f}, {result['max_intensity']:.0f}]")
        
        # Calculate centroid
        coords = np.argwhere(seg_mask)
        centroid = coords.mean(axis=0)
        result["centroid"] = [float(c) for c in centroid]
        print(f"Centroid: {result['centroid']}")
        
        # Check if centroid is in peripheral region (subcutaneous fat should be near edges)
        shape = np.array(seg_mask.shape)
        center = shape / 2
        dist_from_center = np.linalg.norm(centroid[:2] - center[:2])
        max_dist = np.linalg.norm(center[:2])
        periphery_ratio = dist_from_center / max_dist if max_dist > 0 else 0
        result["periphery_ratio"] = float(periphery_ratio)
        print(f"Periphery ratio: {periphery_ratio:.2f} (>0.3 expected for subcutaneous)")
        
        result["analysis_success"] = True
    else:
        result["error"] = "No voxels in segmentation"
        
except Exception as e:
    result["error"] = str(e)
    print(f"Analysis error: {e}")

# Save analysis results
with open(output_json, "w") as f:
    json.dump(result, f, indent=2)

print(f"Analysis saved to {output_json}")
PYEOF

    # Read analysis results
    if [ -f /tmp/seg_analysis.json ]; then
        ANALYSIS_SUCCESS=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('analysis_success', False))" 2>/dev/null || echo "false")
        VOXEL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('voxel_count', 0))" 2>/dev/null || echo "0")
        INTENSITY_COMPLIANCE=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('intensity_compliance', 0))" 2>/dev/null || echo "0")
        MEAN_INTENSITY=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('mean_intensity', 0))" 2>/dev/null || echo "0")
        PERIPHERY_RATIO=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('periphery_ratio', 0))" 2>/dev/null || echo "0")
    fi
fi

# Get window list for trajectory evidence
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
SEGMENT_EDITOR_VISIBLE="false"
if echo "$WINDOWS_LIST" | grep -qi "Segment Editor\|Segmentation"; then
    SEGMENT_EDITOR_VISIBLE="true"
fi

# Check for masking panel interaction evidence
MASKING_CONFIGURED="unknown"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_exists": $SEG_EXISTS,
    "segmentation_file": "$SEG_FILE",
    "segmentation_size_bytes": $SEG_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis_success": $ANALYSIS_SUCCESS,
    "voxel_count": $VOXEL_COUNT,
    "intensity_compliance": $INTENSITY_COMPLIANCE,
    "mean_intensity": $MEAN_INTENSITY,
    "periphery_ratio": $PERIPHERY_RATIO,
    "segment_editor_visible": $SEGMENT_EDITOR_VISIBLE,
    "ct_file": "$CT_FILE",
    "case_id": "$CASE_ID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/intensity_mask_result.json 2>/dev/null || sudo rm -f /tmp/intensity_mask_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/intensity_mask_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/intensity_mask_result.json
chmod 666 /tmp/intensity_mask_result.json 2>/dev/null || sudo chmod 666 /tmp/intensity_mask_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/intensity_mask_result.json"
cat /tmp/intensity_mask_result.json
echo ""
echo "=== Export Complete ==="