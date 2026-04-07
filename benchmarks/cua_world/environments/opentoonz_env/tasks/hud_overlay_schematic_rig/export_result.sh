#!/bin/bash
echo "=== Exporting hud_overlay_schematic_rig result ==="

# Paths
SCENE_FILE="/home/ga/OpenToonz/projects/hud_test/hud_test.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/hud_test"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Scene File
SCENE_EXISTS="false"
SCENE_MTIME=0
if [ -f "$SCENE_FILE" ]; then
    SCENE_EXISTS="true"
    SCENE_MTIME=$(stat -c %Y "$SCENE_FILE")
    # Copy scene file for XML verification
    cp "$SCENE_FILE" /tmp/hud_test_scene.tnz
    chmod 644 /tmp/hud_test_scene.tnz
fi

# 3. Check Render Output
OUTPUT_COUNT=0
OUTPUT_NEW_COUNT=0
LAST_FRAME=""

if [ -d "$OUTPUT_DIR" ]; then
    # Count total PNGs
    OUTPUT_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
    
    # Count files created after task start
    OUTPUT_NEW_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt | wc -l)
    
    # Identify the last frame (alphanumerically last)
    LAST_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | sort | tail -n 1)
    
    # Copy the last frame for visual analysis if it exists
    if [ -n "$LAST_FRAME" ]; then
        cp "$LAST_FRAME" /tmp/hud_last_frame.png
        chmod 644 /tmp/hud_last_frame.png
    fi
fi

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "scene_exists": $SCENE_EXISTS,
    "scene_mtime": $SCENE_MTIME,
    "output_count": $OUTPUT_COUNT,
    "output_new_count": $OUTPUT_NEW_COUNT,
    "last_frame_path": "$LAST_FRAME",
    "scene_xml_path": "/tmp/hud_test_scene.tnz",
    "verification_image_path": "/tmp/hud_last_frame.png"
}
EOF

# Move JSON to accessible location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json