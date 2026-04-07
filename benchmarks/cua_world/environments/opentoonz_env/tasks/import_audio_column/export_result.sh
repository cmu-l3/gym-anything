#!/bin/bash
echo "=== Exporting import_audio_column result ==="

# Paths
SCENE_FILE="/home/ga/OpenToonz/projects/audio_sync_scene/audio_sync_scene.tnz"
AUDIO_SOURCE="/home/ga/OpenToonz/audio/reference_dialogue.wav"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Scene File Existence and Timestamp
SCENE_EXISTS="false"
SCENE_NEWER="false"
SCENE_SIZE_BYTES=0

if [ -f "$SCENE_FILE" ]; then
    SCENE_EXISTS="true"
    SCENE_SIZE_BYTES=$(stat -c %s "$SCENE_FILE")
    SCENE_MTIME=$(stat -c %Y "$SCENE_FILE")
    
    if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
        SCENE_NEWER="true"
    fi
fi

# 3. Verify Audio Content in Scene File (XML Parsing/Grep)
# OpenToonz .tnz files are XML. A sound column usually looks like:
# <level id='1'><path>reference_dialogue.wav</path>...</level>
# or inside a <soundColumn> tag.
HAS_AUDIO_REF="false"
HAS_SOUND_COLUMN="false"

if [ "$SCENE_EXISTS" = "true" ]; then
    # Search for the specific filename in the scene file
    if grep -q "reference_dialogue.wav" "$SCENE_FILE"; then
        HAS_AUDIO_REF="true"
    fi
    
    # Search for Sound Column specific XML tags
    # OpenToonz uses <soundColumn> or type tags for audio levels
    if grep -q "soundColumn" "$SCENE_FILE" || grep -q "SoundLevel" "$SCENE_FILE" || grep -q "type=\"sound\"" "$SCENE_FILE"; then
        HAS_SOUND_COLUMN="true"
    fi
fi

# 4. Check if the audio file was copied/moved into the project directory (common OpenToonz behavior)
PROJECT_DIR=$(dirname "$SCENE_FILE")
AUDIO_IN_PROJECT="false"
# Look for any wav file in the project directory that matches our source name
if find "$PROJECT_DIR" -name "reference_dialogue.wav" | grep -q .; then
    AUDIO_IN_PROJECT="true"
fi

# 5. Check if App is still running
APP_RUNNING=$(pgrep -f opentoonz > /dev/null && echo "true" || echo "false")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scene_exists": $SCENE_EXISTS,
    "scene_newer_than_start": $SCENE_NEWER,
    "scene_size_bytes": $SCENE_SIZE_BYTES,
    "has_audio_reference": $HAS_AUDIO_REF,
    "has_sound_column_tag": $HAS_SOUND_COLUMN,
    "audio_in_project_dir": $AUDIO_IN_PROJECT,
    "app_running": $APP_RUNNING,
    "task_start": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy to output location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="