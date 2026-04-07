#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DIR="/home/ga/Videos/live_score_deliverables"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to dump ffprobe info to JSON reliably inside the container
probe_to_json() {
    local file=$1
    local out_json=$2
    if [ -f "$file" ]; then
        ffprobe -v error -show_format -show_streams -of json "$file" > "$out_json" 2>/dev/null
    else
        echo '{"error": "File not found"}' > "$out_json"
    fi
    chmod 666 "$out_json" 2>/dev/null || true
}

echo "Probing deliverables..."
probe_to_json "$OUTPUT_DIR/projection_master.mp4" "/tmp/projection_info.json"
probe_to_json "$OUTPUT_DIR/conductor_reference.mp4" "/tmp/conductor_info.json"

# Copy manifest to /tmp for safe access by verifier
if [ -f "$OUTPUT_DIR/delivery_manifest.json" ]; then
    cp "$OUTPUT_DIR/delivery_manifest.json" "/tmp/delivery_manifest.json"
    chmod 666 "/tmp/delivery_manifest.json" 2>/dev/null || true
else
    echo '{"error": "Manifest not found"}' > "/tmp/delivery_manifest.json"
fi

# Basic existence checks
PROJECTION_EXISTS=$( [ -f "$OUTPUT_DIR/projection_master.mp4" ] && echo "true" || echo "false" )
CONDUCTOR_EXISTS=$( [ -f "$OUTPUT_DIR/conductor_reference.mp4" ] && echo "true" || echo "false" )

# Export summary JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "projection_exists": $PROJECTION_EXISTS,
    "conductor_exists": $CONDUCTOR_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="