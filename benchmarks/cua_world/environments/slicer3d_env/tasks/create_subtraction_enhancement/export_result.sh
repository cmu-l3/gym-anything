#!/bin/bash
echo "=== Exporting Subtraction Enhancement Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

RESULT_FILE="/tmp/subtraction_task_result.json"
OUTPUT_FILE="/home/ga/Documents/SlicerData/Exports/enhancement_map.nii.gz"
SAMPLE_ID=$(cat /tmp/current_sample_id 2>/dev/null || cat /tmp/brats_sample_id 2>/dev/null || echo "BraTS2021_00000")
CASE_DIR=$(cat /tmp/current_case_dir 2>/dev/null || echo "/home/ga/Documents/SlicerData/BraTS/$SAMPLE_ID")
GT_DIR="/var/lib/slicer/ground_truth"
SCREENSHOTS_DIR="/tmp/task_screenshots"

# Take final screenshot
mkdir -p "$SCREENSHOTS_DIR"
DISPLAY=:1 scrot "${SCREENSHOTS_DIR}/final_state.png" 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_CREATED_AFTER_START="false"
OUTPUT_MTIME=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo 0)
    
    # Check timestamp
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_AFTER_START="true"
    fi
    echo "Output file found: $OUTPUT_FILE ($OUTPUT_SIZE bytes)"
    echo "Output mtime: $OUTPUT_MTIME, Task start: $TASK_START"
fi

# Also check for alternative output locations
ALT_OUTPUT_PATHS=(
    "/home/ga/Documents/SlicerData/enhancement_map.nii.gz"
    "/home/ga/enhancement_map.nii.gz"
    "/home/ga/Documents/enhancement_map.nii.gz"
    "/home/ga/Desktop/enhancement_map.nii.gz"
)

ALT_OUTPUT_FOUND=""
for alt_path in "${ALT_OUTPUT_PATHS[@]}"; do
    if [ -f "$alt_path" ]; then
        ALT_OUTPUT_FOUND="$alt_path"
        echo "Found alternative output at: $alt_path"
        break
    fi
done

# Validate output with Python
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

output_file = "$OUTPUT_FILE"
alt_output = "$ALT_OUTPUT_FOUND"
sample_id = "$SAMPLE_ID"
case_dir = "$CASE_DIR"
gt_dir = "$GT_DIR"
result_file = "$RESULT_FILE"
task_start = int("$TASK_START") if "$TASK_START".isdigit() else 0
task_end = int("$TASK_END") if "$TASK_END".isdigit() else 0

# Use alternative output if primary doesn't exist
if not os.path.exists(output_file) and alt_output and os.path.exists(alt_output):
    output_file = alt_output
    print(f"Using alternative output: {output_file}")

results = {
    "task_start": task_start,
    "task_end": task_end,
    "slicer_running": "$SLICER_RUNNING" == "true",
    "output_exists": os.path.exists(output_file),
    "output_path": output_file,
    "output_size_bytes": 0,
    "output_created_after_start": False,
    "sample_id": sample_id,
    "validation_passed": False,
    "dimensions_match": False,
    "subtraction_valid": False,
    "enhancement_detected": False,
    "enhancement_ratio": 0.0,
    "correlation_with_expected": 0.0,
    "error": None
}

if not os.path.exists(output_file):
    results["error"] = "Output file does not exist"
    with open(result_file, 'w') as f:
        json.dump(results, f, indent=2)
    print(json.dumps(results, indent=2))
    sys.exit(0)

try:
    # Get file info
    results["output_size_bytes"] = os.path.getsize(output_file)
    file_mtime = int(os.path.getmtime(output_file))
    results["output_created_after_start"] = file_mtime > task_start
    
    # Load output
    output_nii = nib.load(output_file)
    output_data = output_nii.get_fdata().astype(np.float32)
    results["output_shape"] = list(output_data.shape)
    
    # Load input T1 to compare dimensions
    t1_path = os.path.join(case_dir, f"{sample_id}_t1.nii.gz")
    t1ce_path = os.path.join(case_dir, f"{sample_id}_t1ce.nii.gz")
    
    if os.path.exists(t1_path):
        t1_nii = nib.load(t1_path)
        t1_shape = t1_nii.shape
        t1_data = t1_nii.get_fdata().astype(np.float32)
        results["input_shape"] = list(t1_shape)
        
        # Check dimensions match
        if output_data.shape == t1_shape:
            results["dimensions_match"] = True
        else:
            print(f"Dimension mismatch: output {output_data.shape} vs input {t1_shape}")
    
    # Calculate output statistics
    brain_mask = output_data != 0
    if np.any(brain_mask):
        results["output_mean"] = float(np.mean(output_data[brain_mask]))
        results["output_std"] = float(np.std(output_data[brain_mask]))
    results["output_max"] = float(np.max(output_data))
    results["output_min"] = float(np.min(output_data))
    
    # Validate subtraction by comparing with expected result
    if os.path.exists(t1_path) and os.path.exists(t1ce_path):
        t1ce_data = nib.load(t1ce_path).get_fdata().astype(np.float32)
        
        # Check output is not identical to inputs
        t1_match = np.allclose(output_data, t1_data, rtol=0.01)
        t1ce_match = np.allclose(output_data, t1ce_data, rtol=0.01)
        
        results["is_copy_of_t1"] = bool(t1_match)
        results["is_copy_of_t1ce"] = bool(t1ce_match)
        
        if not t1_match and not t1ce_match:
            # Check if it looks like a subtraction
            expected_sub = t1ce_data - t1_data
            reversed_sub = t1_data - t1ce_data
            
            # Create mask for valid brain region
            mask = (t1_data > 0) & np.isfinite(output_data) & np.isfinite(expected_sub)
            
            if np.any(mask):
                # Correlation with expected subtraction
                output_flat = output_data[mask].flatten()
                expected_flat = expected_sub[mask].flatten()
                reversed_flat = reversed_sub[mask].flatten()
                
                # Calculate correlations
                corr_expected = np.corrcoef(output_flat, expected_flat)[0, 1]
                corr_reversed = np.corrcoef(output_flat, reversed_flat)[0, 1]
                
                results["correlation_with_expected"] = float(corr_expected) if np.isfinite(corr_expected) else 0.0
                results["correlation_with_reversed"] = float(corr_reversed) if np.isfinite(corr_reversed) else 0.0
                
                # High correlation indicates correct subtraction
                if corr_expected > 0.9:
                    results["subtraction_valid"] = True
                    results["subtraction_order"] = "correct"
                # Negative correlation might indicate reversed subtraction
                elif corr_reversed > 0.9:
                    results["subtraction_reversed"] = True
                    results["subtraction_order"] = "reversed"
                elif corr_expected > 0.7:
                    results["subtraction_valid"] = True
                    results["subtraction_order"] = "approximately_correct"
    
    # Load ground truth segmentation for enhancement detection
    seg_path = os.path.join(gt_dir, f"{sample_id}_seg.nii.gz")
    
    if os.path.exists(seg_path):
        seg = nib.load(seg_path).get_fdata().astype(np.int32)
        enhancing_mask = (seg == 4)  # Enhancing tumor label
        non_tumor_mask = (seg == 0) & (output_data != 0)
        
        if np.any(enhancing_mask) and np.any(non_tumor_mask):
            enhancing_mean = np.mean(output_data[enhancing_mask])
            non_tumor_mean = np.mean(output_data[non_tumor_mask])
            
            results["enhancing_region_mean"] = float(enhancing_mean)
            results["non_tumor_mean"] = float(non_tumor_mean)
            results["enhancing_voxel_count"] = int(np.sum(enhancing_mask))
            
            if abs(non_tumor_mean) > 1e-6:
                ratio = enhancing_mean / (abs(non_tumor_mean) + 1e-6)
                results["enhancement_ratio"] = float(ratio)
                
                # Enhancement should be significantly higher in tumor
                if ratio > 1.5:
                    results["enhancement_detected"] = True
            elif enhancing_mean > 10:  # If background is near zero, check absolute value
                results["enhancement_ratio"] = float(enhancing_mean)
                results["enhancement_detected"] = True
    
    # Overall validation
    results["validation_passed"] = (
        results["dimensions_match"] and
        (results["subtraction_valid"] or results.get("correlation_with_expected", 0) > 0.7)
    )
    
except Exception as e:
    results["error"] = str(e)
    import traceback
    results["traceback"] = traceback.format_exc()

# Save results
with open(result_file, 'w') as f:
    json.dump(results, f, indent=2)

print("=== Validation Results ===")
print(json.dumps(results, indent=2))
PYEOF

# Copy screenshots for verification
if [ -f "${SCREENSHOTS_DIR}/final_state.png" ]; then
    cp "${SCREENSHOTS_DIR}/final_state.png" /tmp/final_screenshot.png 2>/dev/null || true
fi

echo ""
echo "=== Export Complete ==="
echo "Results saved to: $RESULT_FILE"
if [ -f "$RESULT_FILE" ]; then
    cat "$RESULT_FILE"
fi