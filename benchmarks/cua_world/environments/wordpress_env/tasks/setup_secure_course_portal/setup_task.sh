#!/bin/bash
# Setup script for setup_secure_course_portal task (pre_task hook)

echo "=== Setting up Secure Course Portal Task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Record initial page counts
INITIAL_PAGE_COUNT=$(get_post_count "page" "publish")
echo "$INITIAL_PAGE_COUNT" | sudo tee /tmp/initial_page_count > /dev/null
sudo chmod 666 /tmp/initial_page_count
echo "Initial published page count: $INITIAL_PAGE_COUNT"

# ============================================================
# Prepare Real Data (NASA Press Kits & Diagram)
# ============================================================
MATERIALS_DIR="/home/ga/Documents/Spaceflight_Materials"
mkdir -p "$MATERIALS_DIR"

echo "Downloading real historical materials..."

# Apollo 11 Press Kit (NASA History)
if [ ! -f "$MATERIALS_DIR/apollo_11_press_kit.pdf" ]; then
    echo "Downloading Apollo 11 Press Kit..."
    curl -sL "https://history.nasa.gov/alsj/a11/A11_PressKit.pdf" -o "$MATERIALS_DIR/apollo_11_press_kit.pdf" || \
    wget -q "https://history.nasa.gov/alsj/a11/A11_PressKit.pdf" -O "$MATERIALS_DIR/apollo_11_press_kit.pdf"
fi

# Apollo 12 Press Kit (NASA History)
if [ ! -f "$MATERIALS_DIR/apollo_12_press_kit.pdf" ]; then
    echo "Downloading Apollo 12 Press Kit..."
    curl -sL "https://history.nasa.gov/alsj/a12/A12_PressKit.pdf" -o "$MATERIALS_DIR/apollo_12_press_kit.pdf" || \
    wget -q "https://history.nasa.gov/alsj/a12/A12_PressKit.pdf" -O "$MATERIALS_DIR/apollo_12_press_kit.pdf"
fi

# Saturn V Schematic (Wikimedia Commons)
if [ ! -f "$MATERIALS_DIR/saturn_v_diagram.jpg" ]; then
    echo "Downloading Saturn V schematic..."
    curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Saturn_v_schematic.jpg/800px-Saturn_v_schematic.jpg" -o "$MATERIALS_DIR/saturn_v_diagram.jpg" || \
    wget -q "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Saturn_v_schematic.jpg/800px-Saturn_v_schematic.jpg" -O "$MATERIALS_DIR/saturn_v_diagram.jpg"
fi

chown -R ga:ga "$MATERIALS_DIR"
chmod -R 755 "$MATERIALS_DIR"

# Verify downloads
ls -la "$MATERIALS_DIR"

# ============================================================
# Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_startup.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused."
else
    echo "WARNING: No Firefox window found!"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="