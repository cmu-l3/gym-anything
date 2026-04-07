#!/bin/bash
set -e
echo "=== Setting up Switch to Imperial Units task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean starting state
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data from real repository dataset
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# 3. Ensure Subsurface config is fully metric (0=metric, 1=imperial)
# We use Python's configparser to safely manage the INI-style conf file
su - ga -c "python3 - << 'EOF'
import configparser
import os

conf_path = '/home/ga/.config/Subsurface/Subsurface.conf'
os.makedirs(os.path.dirname(conf_path), exist_ok=True)

config = configparser.ConfigParser()
config.optionxform = str
if os.path.exists(conf_path):
    config.read(conf_path)

if 'Units' not in config:
    config.add_section('Units')

# Force metric starting state
config.set('Units', 'length', '0')
config.set('Units', 'pressure', '0')
config.set('Units', 'temperature', '0')
config.set('Units', 'weight', '0')
config.set('Units', 'volume', '0')

with open(conf_path, 'w') as f:
    config.write(f)
EOF"

xhost +local: 2>/dev/null || true

# 4. Launch Subsurface with the dataset
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"

# 5. Wait for UI to initialize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected"
        break
    fi
    sleep 1
done

sleep 3

# 6. Maximize and focus application
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="