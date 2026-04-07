#!/bin/bash
echo "=== Exporting Measured Mile World Creation Result ==="

# Define paths
WORLD_DIR="/opt/bridgecommand/World/MeasuredMile"
SCENARIO_DIR="/opt/bridgecommand/Scenarios/m) Measured Mile Trial"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Data Collection ---

# 1. Check Directory Existence
WORLD_DIR_EXISTS="false"
[ -d "$WORLD_DIR" ] && WORLD_DIR_EXISTS="true"

SCENARIO_DIR_EXISTS="false"
[ -d "$SCENARIO_DIR" ] && SCENARIO_DIR_EXISTS="true"

# 2. Check File Existence & Timestamps
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false_old"
        fi
    else
        echo "false"
    fi
}

FILE_WORLD_INI=$(check_file "$WORLD_DIR/world.ini")
FILE_TERRAIN_INI=$(check_file "$WORLD_DIR/terrain.ini")
FILE_BUOY_INI=$(check_file "$WORLD_DIR/buoy.ini")
FILE_HEIGHT_PNG=$(check_file "$WORLD_DIR/height.png")
FILE_TEXTURE_PNG=$(check_file "$WORLD_DIR/texture.png")
FILE_ENV_INI=$(check_file "$SCENARIO_DIR/environment.ini")

# 3. Read File Contents for Verification
CONTENT_BUOY_INI=""
if [ -f "$WORLD_DIR/buoy.ini" ]; then
    CONTENT_BUOY_INI=$(cat "$WORLD_DIR/buoy.ini" | base64 -w 0)
fi

CONTENT_TERRAIN_INI=""
if [ -f "$WORLD_DIR/terrain.ini" ]; then
    CONTENT_TERRAIN_INI=$(cat "$WORLD_DIR/terrain.ini" | base64 -w 0)
fi

CONTENT_ENV_INI=""
if [ -f "$SCENARIO_DIR/environment.ini" ]; then
    CONTENT_ENV_INI=$(cat "$SCENARIO_DIR/environment.ini" | base64 -w 0)
fi

# 4. Check Image Dimensions (using python if available)
IMG_DIMS="{\"height\": [0,0], \"texture\": [0,0]}"
if command -v python3 &>/dev/null; then
    IMG_DIMS=$(python3 -c "
import struct
import json
import os

def get_png_dims(path):
    if not os.path.exists(path): return [0, 0]
    try:
        with open(path, 'rb') as f:
            head = f.read(24)
            if len(head) != 24: return [0,0]
            w, h = struct.unpack('>II', head[16:24])
            return [w, h]
    except:
        return [0,0]

dims = {
    'height': get_png_dims('$WORLD_DIR/height.png'),
    'texture': get_png_dims('$WORLD_DIR/texture.png')
}
print(json.dumps(dims))
")
fi

# 5. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "world_dir_exists": $WORLD_DIR_EXISTS,
    "scenario_dir_exists": $SCENARIO_DIR_EXISTS,
    "files": {
        "world_ini": "$FILE_WORLD_INI",
        "terrain_ini": "$FILE_TERRAIN_INI",
        "buoy_ini": "$FILE_BUOY_INI",
        "height_png": "$FILE_HEIGHT_PNG",
        "texture_png": "$FILE_TEXTURE_PNG",
        "scenario_env": "$FILE_ENV_INI"
    },
    "image_dims": $IMG_DIMS,
    "content_base64": {
        "buoy_ini": "$CONTENT_BUOY_INI",
        "terrain_ini": "$CONTENT_TERRAIN_INI",
        "env_ini": "$CONTENT_ENV_INI"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"