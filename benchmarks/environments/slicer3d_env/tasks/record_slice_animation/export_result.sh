#!/bin/bash
echo "=== Exporting Record Slice Animation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot before any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Expected output path
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_PATH="$EXPORTS_DIR/brain_axial_sweep.gif"

# ============================================================
# Check output file
# ============================================================
OUTPUT_EXISTS="false"
OUTPUT_SIZE_BYTES=0
OUTPUT_SIZE_KB=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"
VALID_GIF_FORMAT="false"
GIF_FRAME_COUNT=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE_KB=$((OUTPUT_SIZE_BYTES / 1024))
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo "Output file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE_KB KB ($OUTPUT_SIZE_BYTES bytes)"
    echo "  Modified: $OUTPUT_MTIME"
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "  File was created during task execution"
    else
        echo "  WARNING: File modification time is before task start"
    fi
    
    # Validate GIF format by checking magic bytes
    HEADER_BYTES=$(head -c 6 "$OUTPUT_PATH" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    # GIF87a = 474946383761, GIF89a = 474946383961
    if [ "$HEADER_BYTES" = "474946383761" ] || [ "$HEADER_BYTES" = "474946383961" ]; then
        VALID_GIF_FORMAT="true"
        echo "  Valid GIF header detected"
    else
        echo "  WARNING: File does not have valid GIF header (got: $HEADER_BYTES)"
    fi
    
    # Count frames in GIF using Python
    GIF_FRAME_COUNT=$(python3 << 'PYEOF'
import sys
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/SlicerData/Exports/brain_axial_sweep.gif")
    frame_count = 0
    try:
        while True:
            frame_count += 1
            img.seek(img.tell() + 1)
    except EOFError:
        pass
    print(frame_count)
except Exception as e:
    print(0)
PYEOF
)
    echo "  GIF frame count: $GIF_FRAME_COUNT"
    
    # Copy the output file for verification
    cp "$OUTPUT_PATH" /tmp/output_animation.gif 2>/dev/null || true
else
    echo "Output file NOT found at: $OUTPUT_PATH"
    
    # Search for any GIF files that might have been created
    echo "Searching for alternative GIF outputs..."
    FOUND_GIFS=$(find "$EXPORTS_DIR" /home/ga -maxdepth 3 -name "*.gif" -newer /tmp/task_start_time.txt 2>/dev/null | head -5)
    if [ -n "$FOUND_GIFS" ]; then
        echo "Found GIF files created during task:"
        echo "$FOUND_GIFS"
        
        # Use the first found GIF as fallback
        FALLBACK_GIF=$(echo "$FOUND_GIFS" | head -1)
        if [ -n "$FALLBACK_GIF" ] && [ -f "$FALLBACK_GIF" ]; then
            echo "Using fallback GIF: $FALLBACK_GIF"
            cp "$FALLBACK_GIF" /tmp/output_animation.gif 2>/dev/null || true
            OUTPUT_EXISTS="true"
            OUTPUT_SIZE_BYTES=$(stat -c %s "$FALLBACK_GIF" 2>/dev/null || echo "0")
            OUTPUT_SIZE_KB=$((OUTPUT_SIZE_BYTES / 1024))
            OUTPUT_MTIME=$(stat -c %Y "$FALLBACK_GIF" 2>/dev/null || echo "0")
            FILE_CREATED_DURING_TASK="true"
            
            # Check GIF validity for fallback
            HEADER_BYTES=$(head -c 6 "$FALLBACK_GIF" 2>/dev/null | od -An -tx1 | tr -d ' \n')
            if [ "$HEADER_BYTES" = "474946383761" ] || [ "$HEADER_BYTES" = "474946383961" ]; then
                VALID_GIF_FORMAT="true"
            fi
        fi
    fi
fi

# ============================================================
# Check for any new GIF files in exports directory
# ============================================================
FINAL_GIF_COUNT=$(ls -1 "$EXPORTS_DIR"/*.gif 2>/dev/null | wc -l || echo "0")
INITIAL_GIF_COUNT=$(cat /tmp/initial_gif_count.txt 2>/dev/null || echo "0")
NEW_GIF_COUNT=$((FINAL_GIF_COUNT - INITIAL_GIF_COUNT))

# ============================================================
# Check Slicer state
# ============================================================
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Get window information
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
SCREEN_CAPTURE_ACCESSED="false"
if echo "$WINDOW_LIST" | grep -qi "Screen Capture\|ScreenCapture"; then
    SCREEN_CAPTURE_ACCESSED="true"
fi

# ============================================================
# Extract sample frames from GIF for VLM verification
# ============================================================
FRAMES_EXTRACTED="false"
if [ -f /tmp/output_animation.gif ] && [ "$VALID_GIF_FORMAT" = "true" ]; then
    echo "Extracting sample frames from GIF..."
    python3 << 'PYEOF'
import os
try:
    from PIL import Image
    img = Image.open("/tmp/output_animation.gif")
    
    # Count total frames
    frames = []
    try:
        while True:
            frames.append(img.copy())
            img.seek(img.tell() + 1)
    except EOFError:
        pass
    
    total_frames = len(frames)
    if total_frames > 0:
        # Extract frames at 0%, 33%, 66%, 100% positions
        positions = [0, int(total_frames * 0.33), int(total_frames * 0.66), total_frames - 1]
        positions = list(set([min(p, total_frames-1) for p in positions]))
        positions.sort()
        
        os.makedirs("/tmp/gif_frames", exist_ok=True)
        for i, pos in enumerate(positions):
            frame = frames[pos]
            # Convert to RGB if needed
            if frame.mode != 'RGB':
                frame = frame.convert('RGB')
            frame.save(f"/tmp/gif_frames/frame_{i:02d}.png")
        
        print(f"Extracted {len(positions)} frames from {total_frames} total")
        print("SUCCESS")
except Exception as e:
    print(f"Error: {e}")
PYEOF

    if [ -d /tmp/gif_frames ] && [ "$(ls -1 /tmp/gif_frames/*.png 2>/dev/null | wc -l)" -gt 0 ]; then
        FRAMES_EXTRACTED="true"
        echo "Sample frames extracted successfully"
    fi
fi

# ============================================================
# Create result JSON
# ============================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE_BYTES,
    "output_size_kb": $OUTPUT_SIZE_KB,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "valid_gif_format": $VALID_GIF_FORMAT,
    "gif_frame_count": $GIF_FRAME_COUNT,
    "new_gif_count": $NEW_GIF_COUNT,
    "slicer_was_running": $SLICER_RUNNING,
    "screen_capture_accessed": $SCREEN_CAPTURE_ACCESSED,
    "frames_extracted": $FRAMES_EXTRACTED,
    "screenshot_path": "/tmp/task_final.png",
    "gif_copy_path": "/tmp/output_animation.gif",
    "frames_dir": "/tmp/gif_frames"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="