#!/bin/bash
echo "=== Exporting rotoscope_movement_trace results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_DIR="/home/ga/OpenToonz/output/rotoscope_test"
REF_DIR="/home/ga/OpenToonz/samples/bounce_ref"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Rendered Output
OUTPUT_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -o -name "*.tga" -o -name "*.tif" 2>/dev/null | wc -l)
echo "Found $OUTPUT_COUNT rendered frames"

# 2. Check for New Level Creation (Evidence of Drawing)
# Look for .pli (Vector), .tlv (Toonz Raster), or .tif (Raster level) created after start time
NEW_LEVEL_FOUND="false"
NEW_LEVEL_FILE=""

# Check OpenToonz project folders specifically
find /home/ga/OpenToonz -type f \( -name "*.pli" -o -name "*.tlv" \) -newermt "@$TASK_START" 2>/dev/null > /tmp/new_levels.txt

if [ -s /tmp/new_levels.txt ]; then
    NEW_LEVEL_FOUND="true"
    NEW_LEVEL_FILE=$(head -n 1 /tmp/new_levels.txt)
    echo "Found new level file: $NEW_LEVEL_FILE"
fi

# 3. Analyze Output Content (Trace detection)
# We compare the rendered output Frame 1 vs Reference Frame 1
# If they are identical, the user just rendered the reference without tracing.
# If they are different (but not black/white), user added strokes.

TRACE_DETECTED="false"
REF_VISIBLE="false"
ANIMATION_DETECTED="false"

if [ "$OUTPUT_COUNT" -gt 0 ]; then
    # Get first rendered frame
    RENDER_FRAME_1=$(find "$OUTPUT_DIR" -name "*0001*" -o -name "*0000*" | head -n 1)
    REF_FRAME_1="$REF_DIR/bounce.0001.png"
    
    if [ -f "$RENDER_FRAME_1" ] && [ -f "$REF_FRAME_1" ]; then
        # Check 1: Is the reference visible? 
        # Compare Render vs Black frame. If diff is high, content exists.
        # More specifically, check if Render looks somewhat like Ref (SSIM/RMSE)
        # Using ImageMagick compare
        
        # Check if Render is purely white or transparent (bad)
        MEAN_COLOR=$(convert "$RENDER_FRAME_1" -format "%[mean]" info:)
        # 65535 is white (16-bit internal). If very high, probably just white bg.
        
        # Compare Render vs Reference
        # If user traced on top, difference > 0 but < threshold of completely different image
        DIFF_METRIC=$(compare -metric RMSE "$RENDER_FRAME_1" "$REF_FRAME_1" /tmp/diff.png 2>&1 | cut -d' ' -f2 | tr -d '()')
        
        # Python for smarter analysis
        python3 -c "
import sys
from PIL import Image, ImageChops, ImageStat
import numpy as np

try:
    render = Image.open('$RENDER_FRAME_1').convert('RGB').resize((720,540))
    ref = Image.open('$REF_FRAME_1').convert('RGB').resize((720,540))
    
    # 1. Check if Reference Background is visible
    # The reference is Black BG + White Ball.
    # The render should be Black BG + White Ball + Red Trace.
    # We check if the black pixels in Ref are roughly black in Render.
    ref_arr = np.array(ref)
    rend_arr = np.array(render)
    
    # Check corner pixels (should be black)
    corner_sum = np.sum(rend_arr[0:10, 0:10])
    is_black_bg = corner_sum < 5000 # Allow some compression noise
    
    # Check if ball area is bright
    # Center of ball frame 1 is approx 50, 450 (inverted y) -> 50, 90?
    # Let's rely on simple difference.
    
    # Difference
    diff = ImageChops.difference(render, ref)
    stat = ImageStat.Stat(diff)
    mean_diff = sum(stat.mean) / len(stat.mean)
    
    # If mean_diff is very small (< 1), they just rendered the reference (No trace).
    # If mean_diff is moderate (1-50), they likely added lines.
    # If mean_diff is huge (> 100), they might have a white background obscuring the ref.
    
    trace_detected = 1.0 < mean_diff < 100.0
    ref_visible = is_black_bg and mean_diff < 100.0
    
    print(f'MEAN_DIFF={mean_diff}')
    print(f'TRACE_DETECTED={str(trace_detected).lower()}')
    print(f'REF_VISIBLE={str(ref_visible).lower()}')
    
    # Write to file
    with open('/tmp/image_analysis.txt', 'w') as f:
        f.write(f'{trace_detected},{ref_visible}')

except Exception as e:
    print(f'Error: {e}')
"
        IFS=',' read -r TRACE_DETECTED REF_VISIBLE < /tmp/image_analysis.txt || true
        
        # Check Animation: Compare Render Frame 1 vs Render Frame 12
        RENDER_FRAME_12=$(find "$OUTPUT_DIR" -name "*0012*" | head -n 1)
        if [ -f "$RENDER_FRAME_12" ]; then
             DIFF_ANIM=$(compare -metric RMSE "$RENDER_FRAME_1" "$RENDER_FRAME_12" /tmp/anim_diff.png 2>&1 | cut -d' ' -f2 | tr -d '()')
             # If frames differ, animation is present
             if [ "$(echo "$DIFF_ANIM > 0.01" | bc)" -eq 1 ]; then
                ANIMATION_DETECTED="true"
             fi
        fi
    fi
fi

# Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_count": $OUTPUT_COUNT,
    "new_level_found": $NEW_LEVEL_FOUND,
    "new_level_file": "$NEW_LEVEL_FILE",
    "trace_detected": $TRACE_DETECTED,
    "ref_visible": $REF_VISIBLE,
    "animation_detected": $ANIMATION_DETECTED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json