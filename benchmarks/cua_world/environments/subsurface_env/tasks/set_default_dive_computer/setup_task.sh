#!/bin/bash
echo "=== Setting up set_default_dive_computer task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any lingering Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Reset the config file to ensure no lingering dive computer settings are present
CONF_FILE="/home/ga/.config/Subsurface/Subsurface.conf"
if [ -f "$CONF_FILE" ]; then
    # Remove any existing settings that could false-positive the verifier
    sed -i -e '/Shearwater/Id' -e '/Perdix/Id' -e '/rfcomm0/Id' "$CONF_FILE" 2>/dev/null || true
    # Record initial modification time
    stat -c%Y "$CONF_FILE" > /tmp/conf_initial_mtime.txt
else
    echo "0" > /tmp/conf_initial_mtime.txt
fi

xhost +local: 2>/dev/null || true

# Launch Subsurface
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for application window to surface
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected."
        break
    fi
    sleep 2
done
sleep 5

# Dismiss any startup or update dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window to ensure the agent has full visibility
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take an initial screenshot for task documentation
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="