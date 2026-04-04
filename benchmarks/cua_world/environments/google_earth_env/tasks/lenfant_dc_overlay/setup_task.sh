#!/bin/bash
set -e
echo "=== Setting up L'Enfant Plan Overlay Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create data directory
DATA_DIR="/home/ga/Documents/HistoricalMaps"
mkdir -p "$DATA_DIR"
chown -R ga:ga "/home/ga/Documents"

# Download the L'Enfant Plan from Wikimedia Commons (public domain - 1791)
IMAGE_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/8/8c/L%27Enfant_plan.jpg/1200px-L%27Enfant_plan.jpg"
IMAGE_PATH="$DATA_DIR/lenfant_plan_1791.jpg"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Downloading L'Enfant Plan historical map..."
    curl -L -o "$IMAGE_PATH" "$IMAGE_URL" --connect-timeout 30 --max-time 60 || {
        echo "Primary download failed, trying alternative source..."
        # Alternative: Library of Congress
        curl -L -o "$IMAGE_PATH" "https://tile.loc.gov/storage-services/service/gmd/gmd3/g3850/g3850/ct000512.gif" --connect-timeout 30 --max-time 60 || {
            echo "WARNING: Could not download historical map image"
            # Create a placeholder for testing (not ideal but allows task to proceed)
            convert -size 800x600 xc:beige -fill black -pointsize 24 -gravity center \
                -annotate 0 "L'Enfant Plan 1791\n(Placeholder)" "$IMAGE_PATH" 2>/dev/null || true
        }
    }
fi

# Verify image was downloaded
if [ -f "$IMAGE_PATH" ]; then
    IMAGE_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
    echo "Image file ready: $IMAGE_PATH ($IMAGE_SIZE bytes)"
else
    echo "ERROR: Image file not available"
fi

# Set ownership
chown -R ga:ga "$DATA_DIR"

# Record initial My Places state for comparison
MYPLACES="/home/ga/.googleearth/myplaces.kml"
MYPLACES_ALT="/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"

INITIAL_OVERLAY_COUNT=0
if [ -f "$MYPLACES" ]; then
    cp "$MYPLACES" /tmp/myplaces_initial.kml 2>/dev/null || true
    INITIAL_OVERLAY_COUNT=$(grep -c "<GroundOverlay>" "$MYPLACES" 2>/dev/null || echo "0")
elif [ -f "$MYPLACES_ALT" ]; then
    cp "$MYPLACES_ALT" /tmp/myplaces_initial.kml 2>/dev/null || true
    INITIAL_OVERLAY_COUNT=$(grep -c "<GroundOverlay>" "$MYPLACES_ALT" 2>/dev/null || echo "0")
fi
echo "$INITIAL_OVERLAY_COUNT" > /tmp/initial_overlay_count.txt
echo "Initial overlay count: $INITIAL_OVERLAY_COUNT"

# Kill any existing Google Earth for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_setup.log 2>&1 &
sleep 8

# Wait for Google Earth window
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected"
        break
    fi
    sleep 1
done

# Give it more time to fully load
sleep 5

# Maximize and focus window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 2

# Navigate to Washington D.C. National Mall area
echo "Navigating to Washington D.C...."

# Open search (Ctrl+F)
xdotool key ctrl+f
sleep 1

# Type search query
xdotool type "National Mall, Washington DC"
sleep 0.5
xdotool key Return
sleep 6

# Press Escape to close search panel if open
xdotool key Escape
sleep 1

# Zoom out slightly to show more of the National Mall area
xdotool key minus
sleep 0.5
xdotool key minus
sleep 0.5
xdotool key minus
sleep 2

# Take initial screenshot
echo "Capturing initial state..."
scrot /tmp/task_initial_state.png 2>/dev/null || \
    import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record initial state JSON
cat > /tmp/task_initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_overlay_count": $INITIAL_OVERLAY_COUNT,
    "image_path": "$IMAGE_PATH",
    "image_exists": $([ -f "$IMAGE_PATH" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create a ground overlay with the L'Enfant Plan"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Go to Add menu > Image Overlay (or press Ctrl+Shift+O)"
echo "2. Set the Name to: L'Enfant Plan 1791"
echo "3. Browse and select: ~/Documents/HistoricalMaps/lenfant_plan_1791.jpg"
echo "4. Position the overlay over the National Mall area"
echo "5. Scale it to cover from Capitol to Lincoln Memorial"
echo "6. Set transparency to approximately 50%"
echo "7. Click OK to save"
echo ""
echo "Image file location: $IMAGE_PATH"
echo "============================================================"