#!/bin/bash
echo "=== Exporting Hyperstack Reconstruction Result ==="

# Define paths
OUTPUT_FILE="/home/ga/Fiji_Data/results/reconstructed_hyperstack.tif"
RESULT_JSON="/tmp/hyperstack_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
CHANNELS=0
SLICES=0
FRAMES=0
IMAGE_DESCRIPTION=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Use Python to extract TIFF tags (ImageJ saves hyperstack metadata in ImageDescription)
    # We use a python script embedded here to parse the file
    python3 << PYEOF > /tmp/tiff_meta.json
import json
import re
from PIL import Image

filepath = "$OUTPUT_FILE"
meta = {
    "channels": 0,
    "slices": 0,
    "frames": 0,
    "description": ""
}

try:
    img = Image.open(filepath)
    
    # 1. Try generic PIL metadata
    # PIL often puts ImageJ metadata in tag 270 (ImageDescription)
    description = ""
    if 270 in img.tag_v2:
        description = img.tag_v2[270]
    elif hasattr(img, 'info') and 'description' in img.info:
        description = img.info['description']
        
    meta["description"] = str(description)

    # 2. Parse ImageJ metadata string (looks like: "ImageJ=1.53c\nimages=30\nchannels=2\nslices=15...")
    if description:
        # Channels
        c_match = re.search(r'channels=(\d+)', description)
        if c_match:
            meta["channels"] = int(c_match.group(1))
            
        # Slices
        z_match = re.search(r'slices=(\d+)', description)
        if z_match:
            meta["slices"] = int(z_match.group(1))
            
        # Frames
        t_match = re.search(r'frames=(\d+)', description)
        if t_match:
            meta["frames"] = int(t_match.group(1))
            
        # If total images is set but some dimensions missing, infer them
        # (Default ImageJ behavior: if channels=2 is set, slices might be implied)
        images_match = re.search(r'images=(\d+)', description)
        if images_match:
            total = int(images_match.group(1))
            # Basic fallback logic if regex failed
            if meta["channels"] == 0 and meta["slices"] == 0 and meta["frames"] == 0:
                # If we can't parse, we rely on what the agent should have done
                pass
    
    # 3. Fallback: Check n_frames from PIL (for multipage tiff)
    # Note: PIL n_frames usually equals total slices in the file
    if hasattr(img, 'n_frames'):
        meta["pil_n_frames"] = img.n_frames

except Exception as e:
    meta["error"] = str(e)

print(json.dumps(meta))
PYEOF

    # Read the python output
    if [ -f /tmp/tiff_meta.json ]; then
        CHANNELS=$(jq '.channels' /tmp/tiff_meta.json 2>/dev/null || echo "0")
        SLICES=$(jq '.slices' /tmp/tiff_meta.json 2>/dev/null || echo "0")
        FRAMES=$(jq '.frames' /tmp/tiff_meta.json 2>/dev/null || echo "0")
        # If frames/slices/channels are 0, checking PIL n_frames might help verify total count
        PIL_FRAMES=$(jq '.pil_n_frames' /tmp/tiff_meta.json 2>/dev/null || echo "0")
    fi
fi

# Create result JSON
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "channels": $CHANNELS,
    "slices": $SLICES,
    "frames": $FRAMES,
    "total_images": ${PIL_FRAMES:-0}
}
EOF

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"