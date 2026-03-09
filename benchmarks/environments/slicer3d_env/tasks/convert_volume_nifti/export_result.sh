#!/bin/bash
echo "=== Exporting Convert Volume to NIfTI Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
SOURCE_FILE="/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
OUTPUT_FILE="/home/ga/Documents/SlicerData/Exports/MRHead_converted.nii.gz"
OUTPUT_DIR="/home/ga/Documents/SlicerData/Exports"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check for output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created during the task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
else
    echo "Output file NOT found at expected path: $OUTPUT_FILE"
    
    # Search for alternative output locations
    echo "Searching for NIfTI files..."
    FOUND_NIFTI=$(find /home/ga -name "*.nii.gz" -o -name "*.nii" 2>/dev/null | head -5)
    if [ -n "$FOUND_NIFTI" ]; then
        echo "Found NIfTI files:"
        echo "$FOUND_NIFTI"
    fi
fi

# Also check for any .nii or .nii.gz file in the Exports directory
ALT_OUTPUT=""
if [ -d "$OUTPUT_DIR" ]; then
    ALT_OUTPUT=$(find "$OUTPUT_DIR" -name "*.nii*" -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$ALT_OUTPUT" ] && [ "$ALT_OUTPUT" != "$OUTPUT_FILE" ]; then
        echo "Alternative output found: $ALT_OUTPUT"
    fi
fi

# Validate NIfTI file and extract properties
VALID_NIFTI="false"
NIFTI_DIMENSIONS=""
NIFTI_SPACING=""
NIFTI_MEAN_INTENSITY=""
NIFTI_AFFINE_VALID="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Validating NIfTI file..."
    
    python3 << 'PYEOF'
import json
import os
import sys

output_path = "/home/ga/Documents/SlicerData/Exports/MRHead_converted.nii.gz"
result = {
    "valid_nifti": False,
    "dimensions": None,
    "spacing": None,
    "mean_intensity": None,
    "affine_valid": False,
    "error": None
}

try:
    import nibabel as nib
    import numpy as np
    
    # Load the NIfTI file
    img = nib.load(output_path)
    data = img.get_fdata()
    
    result["valid_nifti"] = True
    result["dimensions"] = list(data.shape)
    result["spacing"] = [float(s) for s in img.header.get_zooms()[:3]]
    result["mean_intensity"] = float(np.mean(data))
    
    # Check affine is reasonable (not identity, not all zeros)
    affine = img.affine
    if not np.allclose(affine, np.eye(4)) and not np.allclose(affine, np.zeros((4,4))):
        result["affine_valid"] = True
    
    print(f"Valid NIfTI: True", file=sys.stderr)
    print(f"Dimensions: {result['dimensions']}", file=sys.stderr)
    print(f"Spacing: {result['spacing']}", file=sys.stderr)
    print(f"Mean intensity: {result['mean_intensity']:.2f}", file=sys.stderr)
    
except ImportError as e:
    result["error"] = f"nibabel not available: {e}"
    print(f"nibabel import error: {e}", file=sys.stderr)
except Exception as e:
    result["error"] = str(e)
    print(f"Error validating NIfTI: {e}", file=sys.stderr)

# Save validation result
with open("/tmp/nifti_validation.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

    # Read validation results
    if [ -f /tmp/nifti_validation.json ]; then
        VALID_NIFTI=$(python3 -c "import json; print('true' if json.load(open('/tmp/nifti_validation.json')).get('valid_nifti') else 'false')" 2>/dev/null || echo "false")
        NIFTI_DIMENSIONS=$(python3 -c "import json; d=json.load(open('/tmp/nifti_validation.json')).get('dimensions'); print(json.dumps(d) if d else 'null')" 2>/dev/null || echo "null")
        NIFTI_SPACING=$(python3 -c "import json; s=json.load(open('/tmp/nifti_validation.json')).get('spacing'); print(json.dumps(s) if s else 'null')" 2>/dev/null || echo "null")
        NIFTI_MEAN_INTENSITY=$(python3 -c "import json; print(json.load(open('/tmp/nifti_validation.json')).get('mean_intensity', 0))" 2>/dev/null || echo "0")
        NIFTI_AFFINE_VALID=$(python3 -c "import json; print('true' if json.load(open('/tmp/nifti_validation.json')).get('affine_valid') else 'false')" 2>/dev/null || echo "false")
    fi
fi

# Load source file info for comparison
SOURCE_EXISTS="false"
SOURCE_DIMENSIONS="null"
SOURCE_SPACING="null"

if [ -f /tmp/source_file_info.json ]; then
    SOURCE_EXISTS=$(python3 -c "import json; print('true' if json.load(open('/tmp/source_file_info.json')).get('source_exists') else 'false')" 2>/dev/null || echo "false")
    SOURCE_DIMENSIONS=$(python3 -c "import json; d=json.load(open('/tmp/source_file_info.json')).get('dimensions'); print(json.dumps(d) if d else 'null')" 2>/dev/null || echo "null")
    SOURCE_SPACING=$(python3 -c "import json; s=json.load(open('/tmp/source_file_info.json')).get('spacing'); print(json.dumps(s) if s else 'null')" 2>/dev/null || echo "null")
fi

# Check if dimensions match (within tolerance)
DIMENSIONS_MATCH="false"
if [ "$NIFTI_DIMENSIONS" != "null" ] && [ "$SOURCE_DIMENSIONS" != "null" ]; then
    DIMENSIONS_MATCH=$(python3 << PYEOF
import json
nifti_dims = $NIFTI_DIMENSIONS
source_dims = $SOURCE_DIMENSIONS
if nifti_dims and source_dims and len(nifti_dims) == len(source_dims):
    match = all(abs(n - s) <= 10 for n, s in zip(nifti_dims, source_dims))
    print("true" if match else "false")
else:
    print("false")
PYEOF
)
fi

# Check if spacing matches (within tolerance)
SPACING_MATCH="false"
if [ "$NIFTI_SPACING" != "null" ] && [ "$SOURCE_SPACING" != "null" ]; then
    SPACING_MATCH=$(python3 << PYEOF
import json
nifti_spacing = $NIFTI_SPACING
source_spacing = $SOURCE_SPACING
if nifti_spacing and source_spacing and len(nifti_spacing) == len(source_spacing):
    tolerance = 0.01  # 1% tolerance
    match = all(abs(n - s) / max(s, 0.001) <= tolerance for n, s in zip(nifti_spacing, source_spacing))
    print("true" if match else "false")
else:
    print("false")
PYEOF
)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "source_file_exists": $SOURCE_EXISTS,
    "source_dimensions": $SOURCE_DIMENSIONS,
    "source_spacing": $SOURCE_SPACING,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "valid_nifti": $VALID_NIFTI,
    "nifti_dimensions": $NIFTI_DIMENSIONS,
    "nifti_spacing": $NIFTI_SPACING,
    "nifti_mean_intensity": $NIFTI_MEAN_INTENSITY,
    "nifti_affine_valid": $NIFTI_AFFINE_VALID,
    "dimensions_match": $DIMENSIONS_MATCH,
    "spacing_match": $SPACING_MATCH,
    "expected_output_path": "$OUTPUT_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="