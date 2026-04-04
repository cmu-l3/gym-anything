#!/bin/bash
set -e
echo "=== Exporting prepare_chromakey_render result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/chroma_skull.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Take final screenshot of the desktop (context)
take_screenshot /tmp/task_final.png

# 2. Check output file details
EXISTS="false"
SIZE_BYTES="0"
CREATED_AFTER_START="false"

if [ -f "$OUTPUT_FILE" ]; then
    EXISTS="true"
    SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE")
    MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CREATED_AFTER_START="true"
    fi
fi

# 3. Create JSON result
# We do the heavy image analysis in the python verifier on the host
# to avoid dependency issues inside the container.
cat > /tmp/task_result.json << EOF
{
    "output_exists": $EXISTS,
    "output_path": "$OUTPUT_FILE",
    "file_size_bytes": $SIZE_BYTES,
    "created_after_start": $CREATED_AFTER_START,
    "desktop_screenshot": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions for the host to read
chmod 644 /tmp/task_result.json
chmod 644 "$OUTPUT_FILE" 2>/dev/null || true

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="