#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Target file
OUTPUT_PATH="/home/ga/DICOM/exports/surgical_plan.dcm"

# Use a Python script inside the container to safely analyze the DICOM 
# This guarantees we use the container's pydicom installation and avoid
# missing dependencies on the host during verification.
PYTHON_SCRIPT=$(mktemp)
cat > "$PYTHON_SCRIPT" << 'PYEOF'
import pydicom
import json
import os
import sys

def analyze_dicom():
    result = {
        "output_exists": False,
        "file_created_during_task": False,
        "output_size_bytes": 0,
        "is_valid_dicom": False,
        "sop_class_uid": "",
        "photometric_interpretation": "",
        "samples_per_pixel": 0,
        "has_pixel_data": False,
        "error": None
    }
    
    path = "/home/ga/DICOM/exports/surgical_plan.dcm"
    start_time = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    
    if os.path.exists(path):
        result["output_exists"] = True
        result["output_size_bytes"] = os.path.getsize(path)
        mtime = int(os.path.getmtime(path))
        result["file_created_during_task"] = mtime > start_time
        
        try:
            # Read DICOM without loading massive pixel arrays into memory yet
            ds = pydicom.dcmread(path, stop_before_pixels=True)
            result["is_valid_dicom"] = True
            
            # Extract key metadata to verify it's an exported view, not a source copy
            result["sop_class_uid"] = str(getattr(ds, 'SOPClassUID', ''))
            result["photometric_interpretation"] = str(getattr(ds, 'PhotometricInterpretation', ''))
            result["samples_per_pixel"] = int(getattr(ds, 'SamplesPerPixel', 0))
            
            # Check for pixel data payload
            ds_full = pydicom.dcmread(path)
            result["has_pixel_data"] = 'PixelData' in ds_full and len(ds_full.PixelData) > 0
            
        except Exception as e:
            result["error"] = str(e)
            
    print(json.dumps(result))

if __name__ == "__main__":
    analyze_dicom()
PYEOF

# Run analysis and store JSON
DICOM_ANALYSIS=$(python3 "$PYTHON_SCRIPT" "$TASK_START")

# Check if app is still running
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Combine results
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "dicom_analysis": $DICOM_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" "$PYTHON_SCRIPT"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="