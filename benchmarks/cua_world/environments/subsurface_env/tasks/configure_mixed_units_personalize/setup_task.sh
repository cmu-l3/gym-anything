#!/bin/bash
set -e
echo "=== Setting up Configure Mixed Units task ==="

export DISPLAY="${DISPLAY:-:1}"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing Subsurface instances for clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Set up the configuration file explicitly to Metric defaults
mkdir -p /home/ga/.config/Subsurface
cat > /home/ga/.config/Subsurface/Subsurface.conf << 'CONF_EOF'
[General]
DefaultFilename=/home/ga/Documents/dives.ssrf

[Units]
pressure=0
temperature=0
length=0
volume=0
weight=0
CONF_EOF

chown -R ga:ga /home/ga/.config/Subsurface
chmod 644 /home/ga/.config/Subsurface/Subsurface.conf

# Initial state record
stat -c %Y /home/ga/.config/Subsurface/Subsurface.conf > /tmp/conf_initial_mtime.txt

# Ensure X server access
xhost +local: 2>/dev/null || true

# Launch Subsurface with the sample data
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 setsid subsurface /home/ga/Documents/dives.ssrf >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for Subsurface window to appear
echo "Waiting for Subsurface window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        break
    fi
    sleep 1
done
sleep 3

# Dismiss any residual startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the Subsurface window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="