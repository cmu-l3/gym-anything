#!/bin/bash
echo "=== Exporting Dailies Contact Sheet Pipeline Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will package the entire dailies_output directory into a tarball
# This allows the Python verifier to inspect all 24+ images and JSON files cleanly
OUTPUT_DIR="/home/ga/Videos/dailies_output"
TAR_PATH="/tmp/dailies_output_export.tar.gz"

if [ -d "$OUTPUT_DIR" ]; then
    echo "Found dailies_output directory. Packaging..."
    # Create tarball of the directory contents
    tar -czf "$TAR_PATH" -C /home/ga/Videos dailies_output 2>/dev/null
    chmod 666 "$TAR_PATH" 2>/dev/null || sudo chmod 666 "$TAR_PATH"
else
    echo "Warning: $OUTPUT_DIR does not exist."
fi

# Create a small metadata json to accompany the tarball
META_JSON="/tmp/export_meta.json"
cat > "$META_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "output_dir_exists": $(if [ -d "$OUTPUT_DIR" ]; then echo "true"; else echo "false"; fi),
    "tarball_created": $(if [ -f "$TAR_PATH" ]; then echo "true"; else echo "false"; fi)
}
EOF
chmod 666 "$META_JSON" 2>/dev/null || sudo chmod 666 "$META_JSON"

# Kill VLC
pkill -f vlc || true

echo "Export complete. Artifacts saved to $TAR_PATH and $META_JSON"