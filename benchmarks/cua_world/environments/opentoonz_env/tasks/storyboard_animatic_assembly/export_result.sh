#!/bin/bash
echo "=== Exporting storyboard_animatic_assembly result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/animatic"
STORYBOARD_DIR="/home/ga/OpenToonz/storyboards"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize JSON fields
TOTAL_FRAMES=0
FRAME_10_MATCH="none"
FRAME_30_MATCH="none"
FRAME_50_MATCH="none"
TIMING_CUT_ACCURATE="false"
FILES_CREATED_DURING_TASK="false"

# Helper function to check image similarity (RMSE)
# Returns "match" if RMSE < 1000 (very similar), "mismatch" otherwise
check_match() {
    local target="$1"
    local source="$2"
    if [ ! -f "$target" ] || [ ! -f "$source" ]; then
        echo "missing"
        return
    fi
    
    # Resize source to target size just in case, though they should be 1920x1080
    # Using ImageMagick compare
    local metric=$(compare -metric RMSE "$target" "$source" /tmp/diff.png 2>&1 | cut -d' ' -f2 | cut -d'(' -f2 | cut -d')' -f1)
    
    # Metric is usually 0 (perfect) to 1.0 (total mismatch)
    # We use python to compare float
    local is_match=$(python3 -c "print('true' if $metric < 0.1 else 'false')")
    
    if [ "$is_match" == "true" ]; then
        echo "match"
    else
        echo "mismatch"
    fi
}

# 1. Count Frames
if [ -d "$OUTPUT_DIR" ]; then
    TOTAL_FRAMES=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
    
    # Check if files are new
    NEW_FILES=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt | wc -l)
    if [ "$NEW_FILES" -gt 0 ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# 2. Verify Key Frames Content
# We expect:
# Frame 10 -> key_setup.png
# Frame 30 -> key_anticip.png
# Frame 50 -> key_action.png

# Find actual filenames (OpenToonz usually names them name.0001.png or name.0010.png)
# We find the file that *ends* in 0010.png, 0030.png, etc.
IMG_10=$(find "$OUTPUT_DIR" -name "*0010.png" | head -n 1)
IMG_30=$(find "$OUTPUT_DIR" -name "*0030.png" | head -n 1)
IMG_50=$(find "$OUTPUT_DIR" -name "*0050.png" | head -n 1)

# Timing Check: Frame 24 (Setup) vs Frame 25 (Anticipation)
IMG_24=$(find "$OUTPUT_DIR" -name "*0024.png" | head -n 1)
IMG_25=$(find "$OUTPUT_DIR" -name "*0025.png" | head -n 1)

if [ -n "$IMG_10" ]; then
    FRAME_10_MATCH=$(check_match "$IMG_10" "$STORYBOARD_DIR/key_setup.png")
fi

if [ -n "$IMG_30" ]; then
    FRAME_30_MATCH=$(check_match "$IMG_30" "$STORYBOARD_DIR/key_anticip.png")
fi

if [ -n "$IMG_50" ]; then
    FRAME_50_MATCH=$(check_match "$IMG_50" "$STORYBOARD_DIR/key_action.png")
fi

# 3. precise Timing Check
# Frame 24 should match Setup, Frame 25 should match Anticipation
if [ -n "$IMG_24" ] && [ -n "$IMG_25" ]; then
    MATCH_24=$(check_match "$IMG_24" "$STORYBOARD_DIR/key_setup.png")
    MATCH_25=$(check_match "$IMG_25" "$STORYBOARD_DIR/key_anticip.png")
    
    if [ "$MATCH_24" == "match" ] && [ "$MATCH_25" == "match" ]; then
        TIMING_CUT_ACCURATE="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "total_frames": $TOTAL_FRAMES,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "frame_10_match": "$FRAME_10_MATCH",
    "frame_30_match": "$FRAME_30_MATCH",
    "frame_50_match": "$FRAME_50_MATCH",
    "timing_cut_accurate": $TIMING_CUT_ACCURATE,
    "task_start_time": $TASK_START
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="