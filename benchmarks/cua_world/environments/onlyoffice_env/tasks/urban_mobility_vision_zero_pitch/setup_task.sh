#!/bin/bash
set -euo pipefail

echo "=== Setting up Vision Zero Pitch Task ==="

# Source ONLYOFFICE task utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
WORKSPACE_DIR="/home/ga/Documents/Presentations/Vision_Zero"
IMAGES_DIR="$WORKSPACE_DIR/images"
sudo -u ga mkdir -p "$IMAGES_DIR"

# Generate the raw outline text
cat > "$WORKSPACE_DIR/outline.txt" << 'EOF'
[Slide 1]
Title: Hoboken Vision Zero Action Plan
Subtitle: Achieving Zero Traffic Deaths

[Slide 2]
Title: The Problem
Points:
- Vulnerable road users are at risk
- Unacceptable number of traffic fatalities
- High-speed corridors reduce safety

[Slide 3]
Title: Proposed Solutions
Points:
- Intersection Daylighting to improve visibility
- Traffic calming infrastructure
(Note: Insert daylighting.jpg here)

[Slide 4]
Title: Implementation Timeline
Points:
- Phase 1: High-injury network upgrades (Q1-Q2)
- Phase 2: City-wide speed limit reductions (Q3)

[Slide 5]
Title: Call to Action
Points:
- City Council must adopt resolution 24-05
- Commit funding for safe streets
(Note: Insert protected_bike_lane.jpg here)
EOF

# Download real public-domain images for insertion (with ImageMagick fallback if offline)
echo "Fetching presentation assets..."
wget -q -O "$IMAGES_DIR/daylighting.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/c/ca/Intersection_daylighting_diagram.png/800px-Intersection_daylighting_diagram.png" || \
    convert -size 800x600 xc:lightblue -font /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf -pointsize 40 -fill darkblue -gravity center -draw "text 0,0 'Intersection Daylighting\n(Reference Photo)'" "$IMAGES_DIR/daylighting.jpg"

wget -q -O "$IMAGES_DIR/protected_bike_lane.jpg" "https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/Protected_bike_lane_in_San_Francisco.jpg/800px-Protected_bike_lane_in_San_Francisco.jpg" || \
    convert -size 800x600 xc:lightgreen -font /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf -pointsize 40 -fill darkgreen -gravity center -draw "text 0,0 'Protected Bike Lane\n(Reference Photo)'" "$IMAGES_DIR/protected_bike_lane.jpg"

# Ensure proper permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Kill existing ONLYOFFICE instances to ensure clean state
if command -v kill_onlyoffice &> /dev/null; then
    kill_onlyoffice ga
else
    pkill -u ga -f "onlyoffice-desktopeditors" 2>/dev/null || true
fi
sleep 2

# Launch ONLYOFFICE Presentation Editor directly
echo "Starting ONLYOFFICE Presentation Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:slide > /tmp/onlyoffice_launch.log 2>&1 &"

# Wait for the application window to appear
echo "Waiting for ONLYOFFICE window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "onlyoffice\|desktop editors"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="