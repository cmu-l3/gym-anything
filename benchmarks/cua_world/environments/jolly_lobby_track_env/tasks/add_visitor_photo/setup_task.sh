#!/bin/bash
set -e

echo "=== Setting up add_visitor_photo task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
date +%s > /tmp/task_start_time.txt

# 1. Prepare the photo file
echo "Preparing visitor photo..."
PHOTO_PATH="/home/ga/Documents/visitor_photo_marcus_webb.jpg"
# Using a stable Wikimedia Commons image (Elijah Wood, CC BY-SA 2.0) as a "visitor"
# We rename it to mimic a generic visitor photo
PHOTO_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/8/86/Elijah_Wood_%2848464654922%29_%28cropped%29.jpg/440px-Elijah_Wood_%2848464654922%29_%28cropped%29.jpg"

if [ ! -f "$PHOTO_PATH" ]; then
    wget -q -O "$PHOTO_PATH" "$PHOTO_URL" || \
    curl -s -L -o "$PHOTO_PATH" "$PHOTO_URL"
    
    # Ensure it's a valid size
    if [ -f "$PHOTO_PATH" ]; then
        convert "$PHOTO_PATH" -resize 300x400 "$PHOTO_PATH" 2>/dev/null || true
        chown ga:ga "$PHOTO_PATH"
        echo "Photo downloaded to $PHOTO_PATH"
    else
        echo "ERROR: Failed to download photo"
        # Create a dummy image if download fails (fallback)
        convert -size 300x400 xc:gray +noise Random "$PHOTO_PATH"
        chown ga:ga "$PHOTO_PATH"
    fi
fi

# 2. Launch Lobby Track
echo "Launching Lobby Track..."
# Kill any existing instances
pkill -f "LobbyTrack" 2>/dev/null || true
sleep 2

# Launch
launch_lobbytrack

# 3. Attempt to pre-populate "Marcus Webb" record
# This is "best effort" - the task description handles the case where it fails
# by asking the agent to create it if missing.
echo "Attempting to pre-populate visitor record..."
WID=$(wait_for_lobbytrack_window 10)

if [ -n "$WID" ]; then
    # Focus window
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    sleep 2
    
    # Try to navigate to "Add Visitor" shortcut if possible, 
    # but since we can't be sure of the state, we rely on the agent instructions.
    # We will just ensure the app is focused and ready.
    echo "App ready."
fi

# 4. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="