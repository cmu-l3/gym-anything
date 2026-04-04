#!/bin/bash
set -e
echo "=== Exporting atmosphere_toggle_comparison task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot for evidence
echo "Capturing final screenshot..."
scrot /tmp/task_final_state.png 2>/dev/null || true

# Define output paths
OUTPUT_DIR="/home/ga/Documents"
FILE1="$OUTPUT_DIR/everest_with_atmosphere.png"
FILE2="$OUTPUT_DIR/everest_without_atmosphere.png"

# ================================================================
# Check first file (with atmosphere)
# ================================================================
FILE1_EXISTS="false"
FILE1_SIZE=0
FILE1_MTIME=0
FILE1_CREATED_DURING_TASK="false"
FILE1_WIDTH=0
FILE1_HEIGHT=0

if [ -f "$FILE1" ]; then
    FILE1_EXISTS="true"
    FILE1_SIZE=$(stat -c %s "$FILE1" 2>/dev/null || echo "0")
    FILE1_MTIME=$(stat -c %Y "$FILE1" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$FILE1_MTIME" -gt "$TASK_START" ]; then
        FILE1_CREATED_DURING_TASK="true"
    fi
    
    # Get image dimensions
    DIMS1=$(python3 -c "
from PIL import Image
try:
    img = Image.open('$FILE1')
    print(f'{img.width},{img.height}')
except:
    print('0,0')
" 2>/dev/null || echo "0,0")
    FILE1_WIDTH=$(echo "$DIMS1" | cut -d',' -f1)
    FILE1_HEIGHT=$(echo "$DIMS1" | cut -d',' -f2)
    
    echo "File 1: EXISTS, size=${FILE1_SIZE}, mtime=${FILE1_MTIME}, dims=${FILE1_WIDTH}x${FILE1_HEIGHT}"
else
    echo "File 1: NOT FOUND"
fi

# ================================================================
# Check second file (without atmosphere)
# ================================================================
FILE2_EXISTS="false"
FILE2_SIZE=0
FILE2_MTIME=0
FILE2_CREATED_DURING_TASK="false"
FILE2_WIDTH=0
FILE2_HEIGHT=0

if [ -f "$FILE2" ]; then
    FILE2_EXISTS="true"
    FILE2_SIZE=$(stat -c %s "$FILE2" 2>/dev/null || echo "0")
    FILE2_MTIME=$(stat -c %Y "$FILE2" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$FILE2_MTIME" -gt "$TASK_START" ]; then
        FILE2_CREATED_DURING_TASK="true"
    fi
    
    # Get image dimensions
    DIMS2=$(python3 -c "
from PIL import Image
try:
    img = Image.open('$FILE2')
    print(f'{img.width},{img.height}')
except:
    print('0,0')
" 2>/dev/null || echo "0,0")
    FILE2_WIDTH=$(echo "$DIMS2" | cut -d',' -f1)
    FILE2_HEIGHT=$(echo "$DIMS2" | cut -d',' -f2)
    
    echo "File 2: EXISTS, size=${FILE2_SIZE}, mtime=${FILE2_MTIME}, dims=${FILE2_WIDTH}x${FILE2_HEIGHT}"
else
    echo "File 2: NOT FOUND"
fi

# ================================================================
# Check if images are different (anti-gaming)
# ================================================================
IMAGES_DIFFERENT="false"
PIXEL_DIFFERENCE=0

if [ "$FILE1_EXISTS" = "true" ] && [ "$FILE2_EXISTS" = "true" ]; then
    # Use ImageMagick to compare images
    DIFF_RESULT=$(compare -metric AE "$FILE1" "$FILE2" /tmp/diff_output.png 2>&1 || echo "error")
    
    if [[ "$DIFF_RESULT" =~ ^[0-9]+$ ]]; then
        PIXEL_DIFFERENCE=$DIFF_RESULT
        if [ "$PIXEL_DIFFERENCE" -gt 5000 ]; then
            IMAGES_DIFFERENT="true"
        fi
    else
        # Comparison failed, assume different
        IMAGES_DIFFERENT="true"
        PIXEL_DIFFERENCE=-1
    fi
    echo "Image comparison: pixel_difference=${PIXEL_DIFFERENCE}, different=${IMAGES_DIFFERENT}"
fi

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo "Google Earth running: $GE_RUNNING"
echo "Window title: $GE_WINDOW_TITLE"

# ================================================================
# Create JSON result
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "file1": {
        "path": "$FILE1",
        "exists": $FILE1_EXISTS,
        "size_bytes": $FILE1_SIZE,
        "mtime": $FILE1_MTIME,
        "created_during_task": $FILE1_CREATED_DURING_TASK,
        "width": $FILE1_WIDTH,
        "height": $FILE1_HEIGHT
    },
    "file2": {
        "path": "$FILE2",
        "exists": $FILE2_EXISTS,
        "size_bytes": $FILE2_SIZE,
        "mtime": $FILE2_MTIME,
        "created_during_task": $FILE2_CREATED_DURING_TASK,
        "width": $FILE2_WIDTH,
        "height": $FILE2_HEIGHT
    },
    "comparison": {
        "images_different": $IMAGES_DIFFERENT,
        "pixel_difference": $PIXEL_DIFFERENCE
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "screenshots": {
        "final_state": "/tmp/task_final_state.png",
        "initial_state": "/tmp/task_initial_state.png"
    }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task result exported ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="