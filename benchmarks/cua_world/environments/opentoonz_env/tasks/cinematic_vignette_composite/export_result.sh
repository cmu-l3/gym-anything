#!/bin/bash
echo "=== Exporting cinematic_vignette_composite result ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/vignette"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Directory
# Count PNG files
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -type f | wc -l)

# Check timestamps (Anti-gaming)
# Count files modified AFTER task start
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newermt "@$TASK_START" -type f | wc -l)

# Get the path of the first generated image for analysis
SAMPLE_IMAGE=""
if [ "$FILE_COUNT" -gt 0 ]; then
    SAMPLE_IMAGE=$(find "$OUTPUT_DIR" -name "*.png" -type f | sort | head -n 1)
fi

# 3. Create Result JSON
# We include the path to the sample image so the verifier can copy it out
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_dir": "$OUTPUT_DIR",
    "total_files": $FILE_COUNT,
    "new_files": $NEW_FILES_COUNT,
    "sample_image_path": "$SAMPLE_IMAGE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json