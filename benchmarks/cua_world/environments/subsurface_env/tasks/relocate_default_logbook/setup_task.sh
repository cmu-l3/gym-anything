#!/bin/bash
set -e
echo "=== Setting up relocate_default_logbook task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Kill any existing Subsurface instances for clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Ensure target directories do NOT exist
rm -rf /home/ga/Sync 2>/dev/null || true

# Restore clean sample data (task starts fresh every time)
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
echo "Clean sample data restored: $(stat -c%s /home/ga/Documents/dives.ssrf) bytes"

# Reset Subsurface config to ensure starting state is clean
mkdir -p /home/ga/.config/Subsurface
if [ -f /home/ga/.config/Subsurface/Subsurface.conf ]; then
    # Replace existing DefaultFilename line
    sed -i 's|^DefaultFilename=.*|DefaultFilename=/home/ga/Documents/dives.ssrf|i' /home/ga/.config/Subsurface/Subsurface.conf || true
    # If not present, append to General
    if ! grep -qi "^DefaultFilename=" /home/ga/.config/Subsurface/Subsurface.conf; then
        sed -i '/^\[General\]/a DefaultFilename=/home/ga/Documents/dives.ssrf' /home/ga/.config/Subsurface/Subsurface.conf || true
    fi
else
    cat > /home/ga/.config/Subsurface/Subsurface.conf << 'CONF_EOF'
[General]
DefaultFilename=/home/ga/Documents/dives.ssrf
CONF_EOF
fi
chown -R ga:ga /home/ga/.config/Subsurface

# Ensure X server access
xhost +local: 2>/dev/null || true

# Launch Subsurface with the sample data
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for Subsurface window to appear
echo "Waiting for Subsurface window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
        break
    fi
    sleep 2
done

# Additional wait for full UI initialization
sleep 5

# Dismiss any residual dialogs with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the Subsurface window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="