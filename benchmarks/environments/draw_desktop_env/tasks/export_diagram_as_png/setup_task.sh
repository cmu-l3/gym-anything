#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up export_diagram_as_png task ==="

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

# Copy the hospital ER diagram to working directory
DIAGRAM_FILE="/home/ga/Diagrams/hospital_er_base.drawio"
if [ -f "/workspace/assets/diagrams/hospital_er_base.drawio" ]; then
    cp /workspace/assets/diagrams/hospital_er_base.drawio "$DIAGRAM_FILE"
else
    echo "ERROR: Source diagram not found in assets!"
    exit 1
fi
chown ga:ga "$DIAGRAM_FILE"
chmod 644 "$DIAGRAM_FILE"

# Clean up any existing export file
rm -f /home/ga/Desktop/hospital_er_export.png 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_export_exists
ls -la /home/ga/Desktop/*.png 2>/dev/null > /tmp/initial_png_list || true

# Launch draw.io (without file argument - startup dialog always appears)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_export.log 2>&1 &"

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

# draw.io Desktop ALWAYS shows a "Create New / Open Existing" startup dialog.
# Most reliable pattern: click "Open Existing Diagram" button directly, then
# use Ctrl+L to enter the file path.
echo "Clicking 'Open Existing Diagram' button in startup dialog..."
DISPLAY=:1 xdotool mousemove 993 489 click 1
sleep 2

# Switch to location entry mode in the file dialog
DISPLAY=:1 xdotool key ctrl+l
sleep 1

# Type the full file path
DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$DIAGRAM_FILE"
sleep 1

# Press Enter to open
DISPLAY=:1 xdotool key Return
sleep 5

# Verify the file was opened
FILE_LOADED="false"
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw.io" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "hospital"; then
    echo "Diagram loaded successfully!"
    FILE_LOADED="true"
fi

# Retry with fallback approach if file didn't load
if [ "$FILE_LOADED" = "false" ]; then
    echo "Warning: First attempt may have failed. Window: $WINDOW_TITLE"
    echo "Retrying with Escape -> Ctrl+O fallback..."
    DISPLAY=:1 xdotool key Escape
    sleep 2
    DISPLAY=:1 xdotool key ctrl+o
    sleep 2
    DISPLAY=:1 xdotool key ctrl+l
    sleep 1
    DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$DIAGRAM_FILE"
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 5

    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw.io" | head -1)
    if echo "$WINDOW_TITLE" | grep -qi "hospital"; then
        echo "Diagram loaded on retry!"
    else
        echo "ERROR: Diagram failed to load after retry. Window: $WINDOW_TITLE"
    fi
fi

# Verify draw.io is running
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw.io" | head -1)
    echo "Window: $WINDOW_TITLE"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/export_task_start.png 2>/dev/null || true

echo "=== export_diagram_as_png task setup completed ==="
