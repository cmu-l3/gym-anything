#!/bin/bash
echo "=== Exporting apply_negative_filter_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/negative_fx"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Analyze Output Files
echo "Analyzing output files..."

# Count PNG files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f | wc -l)

# Check timestamps
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f -newer /tmp/task_start_timestamp | wc -l)

# Image Content Analysis (Python)
# We analyze the first generated image to check for inversion.
# Original 'dwanko_run' has a white background (high brightness).
# Inverted should have a black background (low brightness).
# We also check std_dev to ensure it's not a solid black rectangle.

SAMPLE_IMG=$(find "$OUTPUT_DIR" -name "*.png" -type f | head -1)
MEAN_BRIGHTNESS=255
STD_DEV=0
HAS_CONTENT="false"

if [ -n "$SAMPLE_IMG" ]; then
    ANALYSIS=$(python3 -c "
import sys, json
try:
    from PIL import Image
    import numpy as np
    
    img = Image.open('$SAMPLE_IMG').convert('RGB')
    arr = np.array(img)
    
    mean_val = np.mean(arr)
    std_val = np.std(arr)
    
    print(json.dumps({'mean': mean_val, 'std': std_val}))
except Exception as e:
    print(json.dumps({'mean': 255.0, 'std': 0.0, 'error': str(e)}))
")
    MEAN_BRIGHTNESS=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('mean', 255))")
    STD_DEV=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('std', 0))")
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f opentoonz > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Create JSON Result
cat > "$RESULT_JSON" << EOF
{
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "mean_brightness": $MEAN_BRIGHTNESS,
    "std_dev": $STD_DEV,
    "app_running": $APP_RUNNING,
    "sample_image": "$SAMPLE_IMG",
    "timestamp": $(date +%s)
}
EOF

# Ensure readable
chmod 644 "$RESULT_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"