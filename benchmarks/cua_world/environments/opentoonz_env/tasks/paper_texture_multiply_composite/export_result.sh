#!/bin/bash
echo "=== Exporting paper_texture_multiply_composite results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/OpenToonz/output/textured_composite"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize analysis variables
OUTPUT_COUNT=0
FRAMES_CREATED_DURING_TASK=0
AVG_BRIGHTNESS=255
CORNER_BRIGHTNESS=255
TEXTURE_VARIANCE=0
IS_MULTIPLIED="false"
HAS_TEXTURE="false"
FULL_COVERAGE="false"

# Count files
if [ -d "$OUTPUT_DIR" ]; then
    OUTPUT_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
    
    # Check timestamps
    FRAMES_CREATED_DURING_TASK=$(find "$OUTPUT_DIR" -name "*.png" -newermt "@$TASK_START" | wc -l)
fi

# Analyze the first rendered frame using Python
FIRST_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | head -n 1)

if [ -f "$FIRST_FRAME" ]; then
    echo "Analyzing frame: $FIRST_FRAME"
    
    # Python script to analyze image properties
    # 1. Brightness: Should be lower than pure white (255) due to Multiply
    # 2. Variance: Should be high due to texture noise
    # 3. Corners: Should not be white (indicates texture covers frame)
    
    ANALYSIS=$(python3 -c "
import sys
import numpy as np
from PIL import Image

try:
    img = Image.open('$FIRST_FRAME').convert('RGB')
    arr = np.array(img)
    
    # Check dimensions
    h, w, _ = arr.shape
    
    # 1. Global Brightness (Mean)
    # White background (255) * Texture (~240) / 255 ~= 240
    mean_brightness = np.mean(arr)
    
    # 2. Corner Brightness (Check for coverage)
    # Sample 4 corners (10x10 pixels)
    corners = [
        arr[0:10, 0:10], arr[0:10, w-10:w],
        arr[h-10:h, 0:10], arr[h-10:h, w-10:w]
    ]
    corner_means = [np.mean(c) for c in corners]
    max_corner = max(corner_means)
    
    # 3. Texture Variance (Standard Deviation)
    # Calculate std dev of a patch in the background area
    # Assuming character is in middle, take a patch from top-left
    bg_patch = arr[50:150, 50:150]
    std_dev = np.std(bg_patch)
    
    print(f'{mean_brightness},{max_corner},{std_dev}')
    
except Exception as e:
    print('255,255,0') # Default failure values
")

    # Parse Python output
    IFS=',' read -r AVG_BRIGHTNESS CORNER_BRIGHTNESS TEXTURE_VARIANCE <<< "$ANALYSIS"
    
    # Evaluate Multiplied (Mean brightness should be < 250, assuming pure white BG is gone)
    if (( $(echo "$AVG_BRIGHTNESS < 250" | bc -l) )); then
        IS_MULTIPLIED="true"
    fi
    
    # Evaluate Coverage (Max corner brightness should be < 250, if texture covers it)
    if (( $(echo "$CORNER_BRIGHTNESS < 252" | bc -l) )); then
        FULL_COVERAGE="true"
    fi
    
    # Evaluate Texture (Variance > 2.0 indicates noise/grain, flat color is ~0)
    if (( $(echo "$TEXTURE_VARIANCE > 2.0" | bc -l) )); then
        HAS_TEXTURE="true"
    fi
fi

# Check app running
APP_RUNNING=$(pgrep -f "OpenToonz" > /dev/null && echo "true" || echo "false")

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_count": $OUTPUT_COUNT,
    "frames_created_during_task": $FRAMES_CREATED_DURING_TASK,
    "avg_brightness": $AVG_BRIGHTNESS,
    "corner_brightness": $CORNER_BRIGHTNESS,
    "texture_variance": $TEXTURE_VARIANCE,
    "is_multiplied": $IS_MULTIPLIED,
    "has_texture": $HAS_TEXTURE,
    "full_coverage": $FULL_COVERAGE,
    "app_running": $APP_RUNNING
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="