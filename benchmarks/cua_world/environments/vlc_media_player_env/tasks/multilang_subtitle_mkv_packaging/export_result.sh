#!/bin/bash
echo "=== Exporting multilang_subtitle_mkv_packaging results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

MKV_PATH="/home/ga/Videos/release/documentary_multilang.mkv"
MANIFEST_PATH="/home/ga/Videos/release/stream_manifest.json"
XSPF_PATH="/home/ga/Videos/release/spanish_review.xspf"

# Take final screenshot as evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

echo "Extracting MKV metadata..."
# Extract deep MKV info using ffprobe to avoid Python dependency constraints in container
if [ -f "$MKV_PATH" ]; then
    ffprobe -v quiet -print_format json -show_format -show_streams "$MKV_PATH" > /tmp/mkv_probe.json 2>/dev/null
    
    # Extract the first subtitle track (stream 0 out of subtitle streams) for direct timing verification
    ffmpeg -y -i "$MKV_PATH" -map 0:s:0 -f srt /tmp/exported_sub_0.srt 2>/dev/null || true
else
    echo "{}" > /tmp/mkv_probe.json
fi

# Copy XSPF playlist safely
if [ -f "$XSPF_PATH" ]; then
    cp "$XSPF_PATH" /tmp/spanish_review.xspf 2>/dev/null || true
fi

# Copy JSON Manifest safely
if [ -f "$MANIFEST_PATH" ]; then
    cp "$MANIFEST_PATH" /tmp/stream_manifest.json 2>/dev/null || true
fi

echo "Writing outcome wrapper..."
# Save simple task result wrapper
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mkv_exists": $([ -f "$MKV_PATH" ] && echo "true" || echo "false"),
    "xspf_exists": $([ -f "$XSPF_PATH" ] && echo "true" || echo "false"),
    "manifest_exists": $([ -f "$MANIFEST_PATH" ] && echo "true" || echo "false")
}
EOF

# Prevent permission issues during host-side retrieval
chmod 666 /tmp/task_result.json /tmp/mkv_probe.json /tmp/exported_sub_0.srt /tmp/spanish_review.xspf /tmp/stream_manifest.json /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="