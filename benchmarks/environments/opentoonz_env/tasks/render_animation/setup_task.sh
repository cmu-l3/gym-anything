#!/bin/bash
echo "=== Setting up render_animation task ==="

# Ensure output directory exists and is empty
su - ga -c "mkdir -p /home/ga/OpenToonz/outputs"
rm -f /home/ga/OpenToonz/outputs/rendered_animation.mp4 2>/dev/null || true
rm -f /home/ga/OpenToonz/outputs/*.mp4 2>/dev/null || true

# Record initial state - check if sample file exists
SAMPLE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
if [ -f "$SAMPLE_SCENE" ]; then
    echo "true" > /tmp/sample_exists
    echo "Sample scene exists: $SAMPLE_SCENE"
else
    echo "false" > /tmp/sample_exists
    echo "Warning: Sample scene not found at $SAMPLE_SCENE"

    # Try to find any .tnz file
    FOUND_SCENE=$(find /home/ga/OpenToonz/samples -name "*.tnz" 2>/dev/null | head -1)
    if [ -n "$FOUND_SCENE" ]; then
        echo "Found alternative scene: $FOUND_SCENE"
        echo "$FOUND_SCENE" > /tmp/alternative_scene
    fi
fi

# Record any existing output files (should be none)
find /home/ga/OpenToonz/outputs -name "*.mp4" 2>/dev/null > /tmp/initial_outputs || true
INITIAL_COUNT=$(cat /tmp/initial_outputs | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_output_count

# Determine which scene file to open
SCENE_TO_OPEN="$SAMPLE_SCENE"
if [ ! -f "$SCENE_TO_OPEN" ] && [ -f /tmp/alternative_scene ]; then
    SCENE_TO_OPEN=$(cat /tmp/alternative_scene)
fi

# APPROACH: Close OpenToonz and relaunch with the scene file as argument
echo "Relaunching OpenToonz with scene file..."

# Close any existing OpenToonz instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

# Launch OpenToonz with the scene file
if [ -f "$SCENE_TO_OPEN" ]; then
    echo "Launching OpenToonz with: $SCENE_TO_OPEN"

    # Create a launcher script that opens the file
    cat > /tmp/launch_with_scene.sh << LAUNCHER
#!/bin/bash
export DISPLAY=:1
cd /home/ga

# Try launching with file as argument (common pattern for GUI apps)
if [ -x /snap/bin/opentoonz ]; then
    /snap/bin/opentoonz "$SCENE_TO_OPEN" &
elif command -v opentoonz &> /dev/null; then
    opentoonz "$SCENE_TO_OPEN" &
fi
LAUNCHER
    chmod +x /tmp/launch_with_scene.sh

    # Run as ga user
    su - ga -c "DISPLAY=:1 /tmp/launch_with_scene.sh" &

    # Wait for OpenToonz to start
    echo "Waiting for OpenToonz to start with scene..."
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "opentoonz"; then
            echo "OpenToonz window detected after ${i}s"
            break
        fi
        sleep 1
    done

    # Wait additional time for scene to load
    sleep 5

    # Check if scene is loaded by looking at window title
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "opentoonz" | head -1)
    echo "Window title: $WINDOW_TITLE"

    # Dismiss any startup dialogs
    for i in $(seq 1 5); do
        # Press Escape to close dialogs
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
        # Also try clicking a likely "Close" button location
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 0.5
    done

    # If scene still not loaded, try drag-and-drop simulation via xdotool
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "opentoonz" | head -1)
    if ! echo "$WINDOW_TITLE" | grep -qi "dwanko\|\.tnz"; then
        echo "Scene not auto-loaded, trying File > Recent or manual open..."

        # Try using the application menu: File > Load Scene
        DISPLAY=:1 xdotool key alt+f
        sleep 0.5
        DISPLAY=:1 xdotool key l  # Load Scene option
        sleep 2

        # Navigate to the file using file dialog
        # Clear any existing text and type the full path
        DISPLAY=:1 xdotool key ctrl+a
        sleep 0.2
        DISPLAY=:1 xdotool type --clearmodifiers "$SCENE_TO_OPEN"
        sleep 1
        DISPLAY=:1 xdotool key Return
        sleep 3
    fi
else
    echo "Warning: No scene file found, launching OpenToonz empty"
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"
    sleep 10
fi

# Final dialog dismissal
for i in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Take final screenshot showing loaded scene
sleep 2
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

# Final check
FINAL_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "opentoonz" | head -1)
echo "Final window title: $FINAL_TITLE"

echo "=== Task setup complete ==="
echo "Initial output file count: $INITIAL_COUNT"
echo "Scene to open: $SCENE_TO_OPEN"
