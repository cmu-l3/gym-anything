#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

AVI_PATH="/home/ga/Videos/mod_build/intro_cinematic.avi"
PNG_PATH="/home/ga/Videos/mod_build/loading_splash.png"
JSON_PATH="/home/ga/Videos/mod_build/mod_manifest.json"

# Probe the output AVI if it exists to get media information
if [ -f "$AVI_PATH" ]; then
    ffprobe -v error -show_format -show_streams -of json "$AVI_PATH" > /tmp/avi_probe.json 2>/dev/null
else
    echo "{}" > /tmp/avi_probe.json
fi

# Copy outputs to /tmp for easy access by verifier (avoids permission issues)
rm -f /tmp/intro_cinematic.avi /tmp/loading_splash.png /tmp/mod_manifest.json 2>/dev/null || true

if [ -f "$AVI_PATH" ]; then
    cp "$AVI_PATH" /tmp/intro_cinematic.avi
fi

if [ -f "$PNG_PATH" ]; then
    cp "$PNG_PATH" /tmp/loading_splash.png
fi

if [ -f "$JSON_PATH" ]; then
    cp "$JSON_PATH" /tmp/mod_manifest.json
fi

# Set open permissions on the exported files so the verifier can read them easily
chmod 666 /tmp/avi_probe.json /tmp/intro_cinematic.avi /tmp/loading_splash.png /tmp/mod_manifest.json 2>/dev/null || true

# Create basic export summary
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "avi_exists": $([ -f "$AVI_PATH" ] && echo "true" || echo "false"),
    "png_exists": $([ -f "$PNG_PATH" ] && echo "true" || echo "false"),
    "json_exists": $([ -f "$JSON_PATH" ] && echo "true" || echo "false")
}
EOF
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="