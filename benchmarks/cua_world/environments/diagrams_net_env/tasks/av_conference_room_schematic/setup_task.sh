#!/bin/bash
set -e

echo "=== Setting up AV Conference Room Schematic Task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Clean up previous run
rm -f /home/ga/Diagrams/av_schematic.drawio
rm -f /home/ga/Diagrams/av_schematic.pdf
rm -f /tmp/task_result.json

# 3. Create the Scope of Work file
cat > /home/ga/Desktop/av_scope_of_work.txt << 'EOF'
PROJECT: CONF-RM-04 (Medium Zoom Room)
DATE: 2024-05-20
STATUS: FOR CONSTRUCTION

EQUIPMENT LIST:
1. AUDIO INPUT: Shure MXA920 (Ceiling Array Microphone)
   - Power/Data: PoE+ / Dante
2. DSP (PROCESSOR): Q-SYS Core 8 Flex
   - Connection: Networked (Dante)
   - Output: Analog Line Out to Speakers
3. NETWORK SWITCH: Netgear M4250-10G2F-PoE+
   - Role: Central connectivity for all PoE and Dante devices
4. COMPUTE: Lenovo ThinkSmart Core (Zoom Room PC)
   - Connections: HDMI Out, USB, LAN
5. CAMERA: Aver CAM520 Pro2
   - Connection: USB 3.0
6. DISPLAY: Samsung QM55B (55" 4K)
   - Connection: HDMI In
7. SPEAKERS: Ceiling Speakers (Generic)
   - Connection: Analog Audio Cable from DSP

CABLING & CONNECTION REQUIREMENTS:
1. NETWORK/DANTE (Blue, Solid, 2pt):
   - Connect Shure MXA920 to Switch (Port 1)
   - Connect Q-SYS Core 8 Flex to Switch (Port 2)
   - Connect Lenovo PC (LAN) to Switch (Port 3)

2. VIDEO/HDMI (Black, Thick, 4pt):
   - Connect Lenovo PC (HDMI Out) to Samsung Display

3. USB (Grey, Dashed, 1pt):
   - Connect Aver Camera to Lenovo PC

4. ANALOG AUDIO (Green, Solid, 1pt):
   - Connect Q-SYS Core 8 Flex (Line Out) to Ceiling Speakers

INSTRUCTIONS:
- Create a schematic diagram showing all devices and connections.
- Use the specified line styles to distinguish signal types.
- Ensure the topology reflects that audio travels from the Mic to the DSP via the Network Switch (Dante Protocol), not a direct cable.
- Label all devices clearly.
EOF
chown ga:ga /home/ga/Desktop/av_scope_of_work.txt

# 4. Record start time
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
echo "Launching draw.io..."
# Kill any existing instances
pkill -f drawio 2>/dev/null || true
sleep 1

# Start new instance
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        break
    fi
    sleep 1
done

# 6. Handle Update Dialog (Critical)
sleep 5
echo "Dismissing update dialogs..."
# Try escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
# Try clicking "Cancel" button area (approximate)
DISPLAY=:1 xdotool mousemove 1050 580 click 1 2>/dev/null || true
sleep 0.5
# Try escape again
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 7. Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Initial Screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="