#!/bin/bash
echo "=== Exporting draw_vector_overlay_guide results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/OpenToonz/output/guide_overlay"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for rendered output image
OUTPUT_IMAGE=$(find "$OUTPUT_DIR" -name "*.png" -type f -newermt "@$TASK_START" | head -n 1)
OUTPUT_EXISTS="false"
OUTPUT_PATH=""

if [ -n "$OUTPUT_IMAGE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_PATH="$OUTPUT_IMAGE"
fi

# 3. Check for creation of a NEW Vector Level (.pli file)
# We look for .pli files in the OpenToonz directory structure that were created after task start
# and were NOT in the initial list.
NEW_VECTOR_LEVEL_EXISTS="false"
NEW_PLI_PATH=""

# Find all pli files currently
find /home/ga/OpenToonz -name "*.pli" > /tmp/current_pli_files.txt

# Compare with initial list to find new ones
# We also check modification time just in case they overwrote an existing dummy (unlikely but safe)
while IFS= read -r file; do
    # Check if file is new (not in initial list)
    if ! grep -Fxq "$file" /tmp/initial_pli_files.txt; then
        NEW_VECTOR_LEVEL_EXISTS="true"
        NEW_PLI_PATH="$file"
        break
    fi
    
    # Check timestamp if it was modified significantly after start
    F_TIME=$(stat -c %Y "$file")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        # It's tricky to rely on mod time of existing files for "New Level" creation,
        # but if the task implies creating a NEW level, it should be a new file.
        # However, OpenToonz might re-save existing PLIs. 
        # We prioritize NEW files.
        : # Do nothing, wait for new file check
    fi
done < /tmp/current_pli_files.txt

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "new_vector_level_exists": $NEW_VECTOR_LEVEL_EXISTS,
    "new_vector_level_path": "$NEW_PLI_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="