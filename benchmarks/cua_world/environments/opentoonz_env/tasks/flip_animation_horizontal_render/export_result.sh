#!/bin/bash
echo "=== Exporting flip_animation_horizontal_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/flipped_walkcycle"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
echo "Analyzing output files..."

# Count PNG/TGA/TIFF files
FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -type f 2>/dev/null | wc -l)

# Check timestamps (Anti-gaming)
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -type f -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# Calculate total size
TOTAL_SIZE_BYTES=$(du -sb "$OUTPUT_DIR" 2>/dev/null | cut -f1 || echo "0")

# Get path of the first frame for VLM verification
FIRST_FRAME=""
FRAMES=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -type f -newer /tmp/task_start_time.txt 2>/dev/null | sort)
if [ -n "$FRAMES" ]; then
    FIRST_FRAME=$(echo "$FRAMES" | head -1)
fi

# 3. Create JSON Result
# We save the path to the first frame so verifier.py can load it for VLM
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false"),
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "total_size_bytes": $TOTAL_SIZE_BYTES,
    "first_frame_path": "$FIRST_FRAME",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="