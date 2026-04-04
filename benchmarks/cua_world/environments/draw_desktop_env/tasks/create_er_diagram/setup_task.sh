#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up create_er_diagram task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output file
rm -f /home/ga/Desktop/library_er_diagram.drawio 2>/dev/null || true

# Record initial state
INITIAL_FILES=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_FILES" > /tmp/initial_drawio_count

# Launch draw.io (startup dialog always appears)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_er.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for UI to fully load
sleep 5

# Maximize the window for consistent layout
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# draw.io Desktop shows a "Create New / Open Existing" startup dialog.
# For creating a new diagram, press Escape to dismiss it (creates blank diagram).
# The agent will then create the ER diagram from scratch on this blank canvas.
echo "Dismissing startup dialog (creating blank diagram)..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Verify draw.io is running with a blank canvas
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw.io" | head -1)
    echo "Window: $WINDOW_TITLE"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/er_task_start.png 2>/dev/null || true

echo "=== create_er_diagram task setup completed ==="
