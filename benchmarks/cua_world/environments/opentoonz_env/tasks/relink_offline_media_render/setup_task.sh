#!/bin/bash
echo "=== Setting up relink_offline_media_render task ==="

# Define paths
PROJECT_ROOT="/home/ga/OpenToonz/projects/broken_scene"
ASSETS_DIR="/home/ga/OpenToonz/assets/restored_media"
OUTPUT_DIR="/home/ga/OpenToonz/output/relink_test"
SAMPLE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"

# 1. Clean up previous runs
echo "Cleaning up..."
rm -rf "$PROJECT_ROOT" "$ASSETS_DIR" "$OUTPUT_DIR"
su - ga -c "mkdir -p $PROJECT_ROOT"
su - ga -c "mkdir -p $ASSETS_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Prepare the broken scene
# We need to find what files the sample scene uses.
# dwanko_run.tnz usually uses a level named 'dwanko' or similar.
# We will copy the scene and attempt to identify the level file.

# Copy the main scene file
if [ -f "$SAMPLE_SCENE" ]; then
    cp "$SAMPLE_SCENE" "$PROJECT_ROOT/missing_link.tnz"
else
    echo "ERROR: Sample scene not found at $SAMPLE_SCENE"
    exit 1
fi

# Find associated level files (pli, tlv, tif, png) in samples dir
# Usually dwanko_run uses "dwanko.pli" or similar
LEVEL_FILE=$(find /home/ga/OpenToonz/samples -name "dwanko*.pli" -o -name "dwanko*.tlv" | head -1)

if [ -z "$LEVEL_FILE" ]; then
    echo "Warning: Specific level file not found, copying all PLI/TLV files to assets to be safe"
    cp /home/ga/OpenToonz/samples/*.pli "$ASSETS_DIR/" 2>/dev/null || true
    cp /home/ga/OpenToonz/samples/*.tlv "$ASSETS_DIR/" 2>/dev/null || true
else
    echo "Found level file: $LEVEL_FILE"
    # Copy it to the "Restored Media" location
    cp "$LEVEL_FILE" "$ASSETS_DIR/"
fi

# 3. Break the link in the TNZ file
# OpenToonz scene files are XML-ish. We want to change relative paths to absolute broken paths.
# We'll look for path references and replace them.
# The sample usually has simple filenames like <Path>dwanko.pli</Path>

echo "Breaking file paths in scene..."
# Replace "dwanko.pli" (or whatever) with a full bogus path
# We use sed to replace the filename with a broken absolute path
# Note: This is a heuristic. If the file structure is complex, this might need adjustment.
TARGET_LEVEL_NAME=$(basename "$LEVEL_FILE")
BOGUS_PATH="/Volumes/ExternalDrive/Work/ProjectX/Assets/$TARGET_LEVEL_NAME"

# In the TNZ file, paths are often inside <Path> tags or attributes.
# We simply replace the filename with the bogus path.
sed -i "s|$TARGET_LEVEL_NAME|$BOGUS_PATH|g" "$PROJECT_ROOT/missing_link.tnz"

# Set permissions
chown -R ga:ga "$PROJECT_ROOT" "$ASSETS_DIR" "$OUTPUT_DIR"

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenToonz (Empty)
# We want the agent to open the file themselves to see the "Missing Files" dialog or error.
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz started"
            break
        fi
        sleep 1
    done
fi

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Broken scene: $PROJECT_ROOT/missing_link.tnz"
echo "Asset location: $ASSETS_DIR"