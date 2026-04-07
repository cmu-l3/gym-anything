#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create a compressed archive of the album_output directory
# This allows verifier to securely access all deliverables in one copy operation
cd /home/ga/Music
if [ -d "album_output" ]; then
    tar -czf /tmp/album_output.tar.gz album_output/ 2>/dev/null || true
    chmod 666 /tmp/album_output.tar.gz
    OUTPUT_EXISTS="true"
else
    # Create empty tar if missing to avoid copy_from_env crash
    tar -czf /tmp/album_output.tar.gz -T /dev/null
    chmod 666 /tmp/album_output.tar.gz
    OUTPUT_EXISTS="false"
fi

# Create export manifest for top-level verification details
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_dir_exists": $OUTPUT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/album_output.tar.gz and /tmp/task_result.json"
echo "=== Export complete ==="