#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up edit_uml_class_diagram task ==="

# Ensure draw.io is installed
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

# Copy the real-world e-commerce UML diagram to working directory
DIAGRAM_FILE="/home/ga/Diagrams/ecommerce_uml_classes.drawio"
if [ -f "/workspace/assets/diagrams/ecommerce_uml_classes.drawio" ]; then
    cp /workspace/assets/diagrams/ecommerce_uml_classes.drawio "$DIAGRAM_FILE"
else
    echo "ERROR: Source diagram not found in assets!"
    exit 1
fi
chown ga:ga "$DIAGRAM_FILE"
chmod 644 "$DIAGRAM_FILE"

# Record initial state
echo "Recording initial state..."
INITIAL_SHAPES=$(grep -c 'vertex="1"' "$DIAGRAM_FILE" 2>/dev/null || true)
INITIAL_SHAPES=${INITIAL_SHAPES:-0}
INITIAL_EDGES=$(grep -c 'edge="1"' "$DIAGRAM_FILE" 2>/dev/null || true)
INITIAL_EDGES=${INITIAL_EDGES:-0}
INITIAL_SIZE=$(stat --format=%s "$DIAGRAM_FILE" 2>/dev/null || echo "0")
INITIAL_MTIME=$(stat --format=%Y "$DIAGRAM_FILE" 2>/dev/null || echo "0")
INITIAL_MD5=$(md5sum "$DIAGRAM_FILE" 2>/dev/null | awk '{print $1}' || echo "")
echo "$INITIAL_SHAPES" > /tmp/initial_shape_count
echo "$INITIAL_EDGES" > /tmp/initial_edge_count
echo "$INITIAL_SIZE" > /tmp/initial_file_size
echo "$INITIAL_MTIME" > /tmp/initial_file_mtime
echo "$INITIAL_MD5" > /tmp/initial_file_md5

echo "Initial diagram state:"
echo "  - Shapes: $INITIAL_SHAPES"
echo "  - Edges: $INITIAL_EDGES"
echo "  - Size: $INITIAL_SIZE bytes"

# Launch draw.io (without file argument - startup dialog always appears)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_uml.log 2>&1 &"

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
sleep 5

# Maximize the window for consistent layout
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# draw.io Desktop ALWAYS shows a "Create New / Open Existing" startup dialog.
# Most reliable pattern: click "Open Existing Diagram" button directly, then
# use Ctrl+L to enter the file path. This avoids the fragile Escape -> Ctrl+O chain.
echo "Clicking 'Open Existing Diagram' button in startup dialog..."

# The "Open Existing Diagram" button is centered in the dialog.
# In a maximized 1920x1080 window, its coordinates are approximately (993, 489).
# We use xdotool to click it. If the dialog hasn't appeared yet, this click is harmless
# (hits the empty canvas area), and we fall back to Ctrl+O.
DISPLAY=:1 xdotool mousemove 993 489 click 1
sleep 2

# Check if a file dialog appeared (the click should open the draw.io file browser)
# Now use Ctrl+L to switch to location entry mode
DISPLAY=:1 xdotool key ctrl+l
sleep 1

# Type the full file path
DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$DIAGRAM_FILE"
sleep 1

# Press Enter to open
DISPLAY=:1 xdotool key Return
sleep 5

# Verify the file was opened by checking window title
FILE_LOADED="false"
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw.io" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "ecommerce"; then
    echo "Diagram loaded successfully!"
    FILE_LOADED="true"
fi

# Retry with fallback approach if file didn't load
if [ "$FILE_LOADED" = "false" ]; then
    echo "Warning: First attempt may have failed. Window: $WINDOW_TITLE"
    echo "Retrying with Escape -> Ctrl+O fallback..."

    # Press Escape in case a dialog is still open
    DISPLAY=:1 xdotool key Escape
    sleep 2

    # Open file dialog via Ctrl+O
    DISPLAY=:1 xdotool key ctrl+o
    sleep 2

    # Switch to location entry
    DISPLAY=:1 xdotool key ctrl+l
    sleep 1

    # Type path
    DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$DIAGRAM_FILE"
    sleep 1

    # Enter
    DISPLAY=:1 xdotool key Return
    sleep 5

    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw.io" | head -1)
    if echo "$WINDOW_TITLE" | grep -qi "ecommerce"; then
        echo "Diagram loaded on retry!"
    else
        echo "ERROR: Diagram failed to load after retry. Window: $WINDOW_TITLE"
    fi
fi

# Verify draw.io is running with the correct file
if pgrep -f "drawio" > /dev/null; then
    echo "draw.io is running"
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw.io" | head -1)
    echo "Window: $WINDOW_TITLE"
else
    echo "Warning: draw.io may not have started properly"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/uml_task_start.png 2>/dev/null || true

echo "=== edit_uml_class_diagram task setup completed ==="
