#!/bin/bash
# Export script for MRI Stack Formatting task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting MRI Stack Formatting Results ==="

# Define paths
OUTPUT_FILE="/home/ga/ImageJ_Data/processed/mri_preview.tif"
RESULT_JSON="/tmp/mri_stack_result.json"
TASK_START_FILE="/tmp/task_start_time"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to inspect the output TIFF file
# We use Python because bash/ImageMagick tools can be tricky with multi-page TIFFs and bit depths
python3 << PY_SCRIPT
import json
import os
import sys
import time

result = {
    "file_exists": False,
    "file_size": 0,
    "file_mtime": 0,
    "task_start_time": 0,
    "width": 0,
    "height": 0,
    "n_slices": 0,
    "mode": "unknown",
    "dtype": "unknown",
    "is_8bit": False,
    "error": None
}

output_path = "$OUTPUT_FILE"
task_start_path = "$TASK_START_FILE"

# Load task start time
try:
    if os.path.exists(task_start_path):
        with open(task_start_path, 'r') as f:
            result["task_start_time"] = int(f.read().strip())
except Exception as e:
    result["error"] = f"Failed to read start time: {e}"

# Check file
if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(output_path)
    result["file_mtime"] = int(os.path.getmtime(output_path))
    
    try:
        from PIL import Image
        import numpy as np
        
        # Open image
        img = Image.open(output_path)
        
        result["width"] = img.width
        result["height"] = img.height
        result["mode"] = img.mode
        
        # Count frames/slices
        try:
            result["n_slices"] = getattr(img, "n_frames", 1)
        except:
            # Fallback counting
            count = 0
            try:
                while True:
                    count += 1
                    img.seek(count)
            except EOFError:
                pass
            result["n_slices"] = count
            
        # Check bit depth / data type
        # PIL modes: 'L' = 8-bit pixels, 'I;16' = 16-bit
        # We can also convert to numpy to verify
        img.seek(0)
        arr = np.array(img)
        result["dtype"] = str(arr.dtype)
        
        if result["mode"] == 'L' or result["mode"] == 'P':
            result["is_8bit"] = True
        elif arr.dtype == np.uint8:
            result["is_8bit"] = True
            
    except ImportError:
        result["error"] = "PIL/numpy not available"
    except Exception as e:
        result["error"] = f"Image analysis failed: {str(e)}"
else:
    result["error"] = "File not found"

# Save result
with open("$RESULT_JSON", 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported analysis to {RESULT_JSON}")
PY_SCRIPT

# Display result for log
if [ -f "$RESULT_JSON" ]; then
    cat "$RESULT_JSON"
fi

# Ensure permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "=== Export Complete ==="