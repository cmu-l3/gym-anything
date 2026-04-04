#!/bin/bash
# Export script for multichannel_assembly_calibration task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Result ==="

RESULT_PATH="/home/ga/ImageJ_Data/processed/assembled_cell.tif"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Python script to analyze the TIFF file using PIL/Tifffile
# We need to extract:
# 1. Existence
# 2. Channel count (should be Multi-channel/Composite, not RGB flattened)
# 3. Resolution/Calibration
# 4. Color map info (if possible)

ANALYSIS_SCRIPT="/tmp/analyze_tiff.py"
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import sys
import json
import os
import datetime
from PIL import Image
from PIL.TiffTags import TAGS

file_path = sys.argv[1]
output_file = sys.argv[2]
task_start = float(sys.argv[3])

result = {
    "exists": False,
    "created_during_task": False,
    "is_tiff": False,
    "mode": "unknown",
    "channels": 0,
    "x_resolution": 0,
    "y_resolution": 0,
    "resolution_unit": 0,
    "image_description": "",
    "file_size": 0
}

if os.path.exists(file_path):
    result["exists"] = True
    result["file_size"] = os.path.getsize(file_path)
    mtime = os.path.getmtime(file_path)
    if mtime > task_start:
        result["created_during_task"] = True
    
    try:
        img = Image.open(file_path)
        result["is_tiff"] = img.format == "TIFF"
        result["mode"] = img.mode
        
        # Check channels
        # PIL often sees multi-channel TIFFs as having multiple frames or specialized modes
        if hasattr(img, "n_frames"):
            result["frames"] = img.n_frames
        
        # Determine effective channels based on mode
        if img.mode == 'RGB':
            result["channels"] = 3
            result["type"] = "RGB"
        elif img.mode == 'L':
            result["channels"] = 1
            result["type"] = "Grayscale"
        else:
            # Composite TIFFs usually saved by ImageJ might be read differently
            # We look for ImageJ specific metadata in tag 270 (ImageDescription)
            result["channels"] = len(img.getbands())
            result["type"] = "Multi-band"

        # Extract Resolution
        # Tag 282 (XResolution), 283 (YResolution), 296 (ResolutionUnit)
        # ResolutionUnit: 2 = inch, 3 = cm. 
        # ImageJ often writes "microns" in specific ImageJ tags or converts to standard
        # If Set Scale was used, ImageJ modifies XResolution/YResolution
        
        meta_dict = {TAGS[key]: img.tag[key] for key in img.tag_v2}
        
        if 'XResolution' in meta_dict:
            num, den = meta_dict['XResolution']
            # If 0.16 microns/pixel, resolution is 1/0.16 pixels/micron = 6.25 pixels/unit
            result["x_resolution_val"] = num / den if den != 0 else 0
            
        if 'YResolution' in meta_dict:
            num, den = meta_dict['YResolution']
            result["y_resolution_val"] = num / den if den != 0 else 0
            
        if 'ResolutionUnit' in meta_dict:
            result["resolution_unit"] = meta_dict['ResolutionUnit']
            
        if 'ImageDescription' in meta_dict:
            # ImageJ puts calibration info here stringified
            result["image_description"] = str(meta_dict['ImageDescription'])

    except Exception as e:
        result["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Run analysis
if [ -f "$RESULT_PATH" ]; then
    python3 "$ANALYSIS_SCRIPT" "$RESULT_PATH" "/tmp/tiff_analysis.json" "$TASK_START"
else
    echo '{"exists": false}' > /tmp/tiff_analysis.json
fi

# Combine with screenshot info
cat > /tmp/final_result.json << EOF
{
    "task_start": $TASK_START,
    "tiff_analysis": $(cat /tmp/tiff_analysis.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/final_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="