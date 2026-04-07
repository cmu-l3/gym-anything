#!/bin/bash
set -e
echo "=== Setting up Cleanup & Paint Task ==="

# 1. Define Paths
ASSET_DIR="/home/ga/OpenToonz/assets/scans"
OUTPUT_DIR="/home/ga/OpenToonz/output/ink_and_paint"

# 2. Cleanup Previous Runs
rm -rf "$ASSET_DIR"
rm -rf "$OUTPUT_DIR"
su - ga -c "mkdir -p $ASSET_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 3. Generate "Scanned" Data (Simulated Pencil Drawings)
# We generate 5 frames of a moving black circle on white background
echo "Generating scanned assets..."

# Ensure ImageMagick is available
if ! command -v convert &> /dev/null; then
    echo "ImageMagick not found, installing..."
    apt-get update && apt-get install -y imagemagick
fi

# Geometry matching metadata: Y=500, R=100, StartX=340, StepX=40
for i in {1..5}; do
    FRAME_NUM=$(printf "%04d" $i)
    CX=$((300 + i * 40))
    CY=500
    R=100
    X0=$((CX - R))
    Y0=$((CY - R))
    X1=$((CX + R))
    Y1=$((CY + R))
    
    # Create a 'scanned' look: White background, Black circle
    # We add a tiny bit of noise/blur to make it realistic for cleanup if possible, 
    # but for this task, clean lines are fine.
    convert -size 1920x1080 xc:white \
        -fill white -stroke black -strokewidth 5 \
        -draw "circle $CX,$CY $X1,$CY" \
        "$ASSET_DIR/scan_$FRAME_NUM.jpg"
done

# Set permissions
chown -R ga:ga "/home/ga/OpenToonz/assets"
chmod -R 777 "$ASSET_DIR"

# 4. Start OpenToonz
echo "Starting OpenToonz..."
# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch OpenToonz if not running
if ! pgrep -f "opentoonz" > /dev/null; then
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and Focus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true
sleep 2

# Dismiss any startup popups (common in OpenToonz)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 5. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Assets generated in: $ASSET_DIR"
echo "Expected output in: $OUTPUT_DIR"