#!/bin/bash
set -e

echo "=== Setting up create_network_diagram task ==="

# Ensure draw.io is installed
if [ ! -f /opt/drawio/drawio.AppImage ]; then
    echo "ERROR: draw.io AppImage not found!"
    exit 1
fi

# Clean up any existing diagram file
rm -f /home/ga/Desktop/office_network.drawio 2>/dev/null || true

# Record initial state
INITIAL_FILES=$(ls -la /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_FILES" > /tmp/initial_drawio_count

# Launch draw.io with a new blank diagram
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /tmp/drawio_network.log 2>&1 &"

# Wait for draw.io window to appear
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 4

# IMPORTANT: Aggressively dismiss the "Update Available" dialog if it appears
# The update dialog appears BEFORE "Create New Diagram" dialog and blocks interaction
# We use multiple methods: Escape key, Tab+Enter (to select Cancel), and direct click
echo "Checking for and dismissing update dialog..."

dismiss_update_dialog() {
    # Method 1: Try Escape key
    DISPLAY=:1 xdotool key Escape
    sleep 0.3

    # Method 2: Try Tab then Enter (to navigate to Cancel button)
    DISPLAY=:1 xdotool key Tab Tab Enter
    sleep 0.3

    # Method 3: Try clicking Cancel button location (typical dialog button positions)
    # Update dialogs typically have Cancel button on the right side of the dialog
    # Get window geometry and click likely Cancel button location
    WIN_ID=$(DISPLAY=:1 xdotool search --name "draw.io" 2>/dev/null | head -1)
    if [ -n "$WIN_ID" ]; then
        # Get window geometry
        WIN_GEO=$(DISPLAY=:1 xdotool getwindowgeometry "$WIN_ID" 2>/dev/null || true)
        if [ -n "$WIN_GEO" ]; then
            # Click at center-right area where Cancel typically is (for 1920x1080 screen)
            # Update dialog Cancel is usually around x=1050, y=580 for centered dialog
            DISPLAY=:1 xdotool mousemove 1050 580 click 1 2>/dev/null || true
            sleep 0.2
        fi
    fi
}

# Try dismissal multiple times with verification
UPDATE_DISMISSED=false
for attempt in $(seq 1 15); do
    # Check if update dialog is present
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "update|confirm"; then
        echo "Update dialog detected (attempt $attempt), attempting dismissal..."
        dismiss_update_dialog
        sleep 0.5
    else
        echo "Update dialog not detected or dismissed successfully"
        UPDATE_DISMISSED=true
        break
    fi
done

if [ "$UPDATE_DISMISSED" = "false" ]; then
    echo "WARNING: Update dialog may still be present after 15 attempts"
    # Final aggressive attempt - multiple escapes
    for i in $(seq 1 5); do
        DISPLAY=:1 xdotool key Escape
        sleep 0.2
    done
fi

# Wait for the Create New Diagram dialog to be visible
sleep 2

# Verify draw.io is running
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
    # Check window title to confirm state
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw.io" | head -1)
    echo "Window: $WINDOW_TITLE"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot for reference
DISPLAY=:1 scrot /tmp/network_task_start.png 2>/dev/null || true

# Agent starts at the "Create New Diagram" / "Open Existing Diagram" dialog
# Task description instructs agent to click "Create New Diagram" to begin

echo "=== create_network_diagram task setup completed! ==="
echo ""
echo "Instructions for agent:"
echo "1. draw.io is open showing 'Create New Diagram' dialog"
echo "2. Click 'Create New Diagram' to get a blank canvas"
echo "3. Create a network topology diagram with these elements:"
echo "   - Internet cloud shape at the top"
echo "   - Router/Firewall rectangle connected to Internet"
echo "   - Switch rectangle connected to the Router"
echo "   - Three PC rectangles connected to the Switch"
echo "   - One Server rectangle connected to the Switch"
echo "4. Add text labels to each shape"
echo "5. Connect all devices with lines"
echo "6. Save as 'office_network.drawio' on the Desktop"
