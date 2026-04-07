#!/bin/bash
echo "=== Exporting particle_snow_overlay results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/particle_snow"
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot of the UI
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
echo "Analyzing output directory: $OUTPUT_DIR"
FRAME_COUNT=0
TOTAL_SIZE=0
NEW_FILES_COUNT=0
FIRST_FRAME_PATH=""

if [ -d "$OUTPUT_DIR" ]; then
    # Count PNG/TGA files
    FRAME_COUNT=$(find "$OUTPUT_DIR" -type f \( -name "*.png" -o -name "*.tga" \) | wc -l)
    
    # Calculate total size
    TOTAL_SIZE=$(du -sb "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
    
    # Check timestamps
    NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -type f \( -name "*.png" -o -name "*.tga" \) -newermt "@$TASK_START" | wc -l)
    
    # Find the first frame for VLM verification
    FIRST_FRAME_PATH=$(find "$OUTPUT_DIR" -type f \( -name "*.png" -o -name "*.tga" \) | sort | head -n 1)
fi

# 3. Analyze Scene Modification
SCENE_MODIFIED="false"
CURRENT_HASH=$(md5sum "$SCENE_PATH" 2>/dev/null | awk '{print $1}')
INITIAL_HASH=$(cat /tmp/scene_initial_hash.txt 2>/dev/null || echo "")

if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
    SCENE_MODIFIED="true"
fi

# Check scene file timestamp
SCENE_MTIME=$(stat -c %Y "$SCENE_PATH" 2>/dev/null || echo "0")
if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
    SCENE_MODIFIED="true"
fi

# 4. Prepare result for verification
# We copy the first rendered frame to /tmp/rendered_sample.png so verifier.py can pick it up
RENDERED_SAMPLE_EXISTS="false"
if [ -n "$FIRST_FRAME_PATH" ] && [ -f "$FIRST_FRAME_PATH" ]; then
    cp "$FIRST_FRAME_PATH" /tmp/rendered_sample.png
    RENDERED_SAMPLE_EXISTS="true"
fi

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "frame_count": $FRAME_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "total_size_bytes": ${TOTAL_SIZE:-0},
    "scene_modified": $SCENE_MODIFIED,
    "rendered_sample_exists": $RENDERED_SAMPLE_EXISTS,
    "task_start_time": $TASK_START,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false")
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="