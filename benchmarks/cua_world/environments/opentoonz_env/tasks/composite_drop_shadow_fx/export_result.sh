#!/bin/bash
echo "=== Exporting composite_drop_shadow_fx results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/OpenToonz/output/shadow"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check for output files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f | wc -l)
echo "Found $FILE_COUNT PNG files."

# 2. Python Image Analysis (Shadow Detection)
# We run this inside the container to generate a JSON report
cat > /tmp/analyze_shadow.py << 'EOF'
import os
import glob
import json
import numpy as np
from PIL import Image

output_dir = "/home/ga/OpenToonz/output/shadow"
files = sorted(glob.glob(os.path.join(output_dir, "*.png")))

results = {
    "analyzed_frames": 0,
    "has_alpha_pixels": False,
    "has_shadow_pixels": False,
    "shadow_offset_detected": False,
    "avg_offset_x": 0.0,
    "avg_offset_y": 0.0,
    "foreground_visible": False
}

if files:
    offsets_x = []
    offsets_y = []
    shadow_detections = 0
    fg_detections = 0

    # Analyze first, middle, and last frame to save time
    indices = [0, len(files)//2, len(files)-1]
    # Remove duplicates if few frames
    indices = sorted(list(set(indices)))
    
    for idx in indices:
        try:
            img = Image.open(files[idx]).convert("RGBA")
            arr = np.array(img)
            
            # Split channels
            r, g, b, a = arr[:,:,0], arr[:,:,1], arr[:,:,2], arr[:,:,3]
            
            # 1. Identify Foreground (Character) vs Shadow
            # Character: High Alpha (>200) AND Color (Saturation) or High Value
            # Shadow: Mid Alpha (20-200) OR (High Alpha AND Very Dark/Black)
            
            # Mask for transparent background
            bg_mask = (a < 20)
            
            # Mask for semi-transparent shadow (typical for FX)
            shadow_mask_transp = (a >= 20) & (a < 220)
            
            # Mask for solid-ish pixels
            solid_mask = (a >= 220)
            
            # Refine solid pixels: Dark (Shadow) vs Light/Color (Character)
            # Calculate luminance
            lum = 0.299*r + 0.587*g + 0.114*b
            
            # Solid Shadow: Solid Alpha + Low Luminance (< 40)
            shadow_mask_solid = solid_mask & (lum < 40)
            
            # Character: Solid Alpha + Higher Luminance (> 40)
            # (Dwanko is colored/white, so this works)
            char_mask = solid_mask & (lum >= 40)
            
            # Combined Shadow Mask
            shadow_mask = shadow_mask_transp | shadow_mask_solid
            
            # Metrics
            results["has_alpha_pixels"] = True
            
            if np.sum(shadow_mask) > 100:
                shadow_detections += 1
                results["has_shadow_pixels"] = True
                
            if np.sum(char_mask) > 100:
                fg_detections += 1
                results["foreground_visible"] = True

            # Calculate Centroids
            if np.sum(shadow_mask) > 0 and np.sum(char_mask) > 0:
                y_s, x_s = np.indices(shadow_mask.shape)
                center_shadow_y = np.average(y_s, weights=shadow_mask)
                center_shadow_x = np.average(x_s, weights=shadow_mask)
                
                y_c, x_c = np.indices(char_mask.shape)
                center_char_y = np.average(y_c, weights=char_mask)
                center_char_x = np.average(x_c, weights=char_mask)
                
                # Offset vector from Character TO Shadow
                off_x = center_shadow_x - center_char_x
                off_y = center_shadow_y - center_char_y
                
                offsets_x.append(off_x)
                offsets_y.append(off_y)
                
        except Exception as e:
            print(f"Error analyzing frame {idx}: {e}")

    results["analyzed_frames"] = len(indices)
    
    if offsets_x:
        results["avg_offset_x"] = float(np.mean(offsets_x))
        results["avg_offset_y"] = float(np.mean(offsets_y))
        
        # Bottom-Right logic:
        # X should be positive (Right)
        # Y should be positive (Down, usually image coords 0,0 is top-left)
        if results["avg_offset_x"] > 2 and results["avg_offset_y"] > 2:
            results["shadow_offset_detected"] = True

print(json.dumps(results))
EOF

# Run python script
if [ "$FILE_COUNT" -gt 0 ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_shadow.py)
else
    ANALYSIS_JSON="{}"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Analysis complete."
cat /tmp/task_result.json
echo "=== Export complete ==="