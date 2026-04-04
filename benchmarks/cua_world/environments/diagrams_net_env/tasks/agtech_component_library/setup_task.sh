#!/bin/bash
set -e

echo "=== Setting up AgTech Component Library Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Diagrams /home/ga/Desktop

# 2. Clean previous run artifacts
rm -f /home/ga/Diagrams/SmartGrow_Lib.xml
rm -f /home/ga/Diagrams/field_deployment.drawio
rm -f /home/ga/Diagrams/field_deployment.xml

# 3. Create Device Specs File
cat > /home/ga/Desktop/device_specs.txt << 'EOF'
SMARTGROW DEVICE VISUAL STANDARDS
=================================

1. SoilProbe-X1
   ----------------
   Composition:
     - Body: Vertical Rectangle. Fill Color: Green (#d5e8d4). Stroke: Black.
     - Tip: Triangle pointing down, attached to bottom of Body. Fill Color: Brown (#a0522d).
     - Label: "Probe" (inside Body or group).
   REQUIREMENT: Select all parts -> Right Click -> Group.

2. Hub-Gateway-Z
   ----------------
   Composition:
     - Body: Square. Fill Color: Blue (#dae8fc). Stroke: Black.
     - Antenna: Small Circle/Ellipse, attached to top edge. Fill: White (#ffffff) or None.
     - Status LED: Small Circle inside body. Fill: Red (#ff0000).
     - Label: "Hub" (inside Body or group).
   REQUIREMENT: Select all parts -> Right Click -> Group.

TASK INSTRUCTIONS:
1. Create these two symbols. Group the components for each.
2. Store them in a new custom library file: ~/Diagrams/SmartGrow_Lib.xml
3. Create a diagram ~/Diagrams/field_deployment.drawio showing:
   - 1 Hub
   - 3 Probes
   - Lines connecting the Hub to each Probe.
EOF
chown ga:ga /home/ga/Desktop/device_specs.txt
chmod 644 /home/ga/Desktop/device_specs.txt

# 4. Record start time
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
echo "Launching draw.io..."
# Kill any existing instances
pkill -f drawio 2>/dev/null || true
sleep 1

# Launch as ga user
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /tmp/drawio.log 2>&1 &"

# 6. Wait for window and dismiss update dialogs
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done
sleep 5

# Aggressive update dialog dismissal
echo "Dismissing update dialogs..."
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "update|confirm"; then
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    fi
done
# Blind escape just in case
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool key Escape

# 7. Maximize window
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
    DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="