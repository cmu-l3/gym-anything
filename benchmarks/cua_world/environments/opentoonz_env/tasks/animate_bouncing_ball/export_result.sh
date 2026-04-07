#!/bin/bash
echo "=== Exporting animate_bouncing_ball result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/bouncing_ball"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Count output files (PNGs)
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)

# 2. Identify key frame files
# OpenToonz usually names output like name.0001.png or name_0001.png
# We sort alphamerically to find the sequence
SORTED_FILES=($(find "$OUTPUT_DIR" -name "*.png" | sort))

# Get paths for Frame 1, 12, and 24 (arrays are 0-indexed)
# We check if we have enough frames first
FRAME_1_PATH=""
FRAME_12_PATH=""
FRAME_24_PATH=""

if [ ${#SORTED_FILES[@]} -ge 1 ]; then
    FRAME_1_PATH="${SORTED_FILES[0]}"
fi
if [ ${#SORTED_FILES[@]} -ge 12 ]; then
    FRAME_12_PATH="${SORTED_FILES[11]}"
fi
if [ ${#SORTED_FILES[@]} -ge 24 ]; then
    FRAME_24_PATH="${SORTED_FILES[23]}"
fi

# 3. Check timestamps (Anti-gaming)
FILES_NEWER_THAN_START=0
if [ "$FILE_COUNT" -gt 0 ]; then
    FILES_NEWER_THAN_START=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt | wc -l)
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_count": $FILE_COUNT,
    "files_newer_than_start": $FILES_NEWER_THAN_START,
    "frame_1_path": "$FRAME_1_PATH",
    "frame_12_path": "$FRAME_12_PATH",
    "frame_24_path": "$FRAME_24_PATH",
    "output_dir": "$OUTPUT_DIR"
}
EOF

# Move JSON to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy key frames to /tmp for easy extraction by verifier (avoiding permission issues in deeply nested user dirs)
if [ -f "$FRAME_1_PATH" ]; then cp "$FRAME_1_PATH" /tmp/frame_1.png; chmod 666 /tmp/frame_1.png; fi
if [ -f "$FRAME_12_PATH" ]; then cp "$FRAME_12_PATH" /tmp/frame_12.png; chmod 666 /tmp/frame_12.png; fi
if [ -f "$FRAME_24_PATH" ]; then cp "$FRAME_24_PATH" /tmp/frame_24.png; chmod 666 /tmp/frame_24.png; fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="