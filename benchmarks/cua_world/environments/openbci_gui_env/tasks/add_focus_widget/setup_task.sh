#!/bin/bash
set -e
echo "=== Setting up add_focus_widget task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || source /workspace/utils/openbci_utils.sh || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any existing instances
pkill -f "OpenBCI_GUI" 2>/dev/null || true
pkill -f "java" 2>/dev/null || true # OpenBCI is java-based
sleep 2

# 2. Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"

# 3. Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null 2>&1; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5 # Wait for splash screen to finish

# 4. Automate "Start Session" for Synthetic Board
# The GUI starts at the System Control Panel.
# "Synthetic (Algorithmic)" is usually selected by default in the list.
# We just need to click "START SESSION".
# Coordinates for 1920x1080 (approximate based on v5 UI):
# Start Session button is roughly at center-left or top-left depending on version.
# In v5.2.2 default:
# - 'Synthetic' option: ~ (400, 300)
# - 'Start Session' button: ~ (400, 600) or (960, 800) depending on layout.
# We'll use a safer approach: generic 'Enter' key might work if focused,
# but mouse clicks are more reliable for this UI.

echo "Starting Synthetic Session..."
# Focus window
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true
sleep 1

# Click "Synthetic" (just in case) - Left side list
DISPLAY=:1 xdotool mousemove 200 300 click 1
sleep 0.5

# Click "Start Session" - Usually a large button near the bottom of the first column
# Try multiple common locations for v5
DISPLAY=:1 xdotool mousemove 200 600 click 1
sleep 1
DISPLAY=:1 xdotool mousemove 350 650 click 1 # Backup location
sleep 2

# 5. Wait for Session to Load (Streaming View)
echo "Waiting for session to load..."
sleep 5

# 6. Ensure Focus Widget is NOT present
# By default, layout often has Time Series, FFT, Networking, Head Plot.
# We will iterate through a few common widget slot dropdown locations and set them to "Head Plot" or "Time Series"
# to ensure "Focus" is not visible.
#
# Common Widget Dropdown locations (Top-left of panels):
# Panel 1 (Top Left): Fixed? Usually Time Series.
# Panel 2 (Top Right): ~ (980, 140)
# Panel 3 (Bottom Right): ~ (980, 600)
#
# We'll click the Top Right dropdown and select "Head Plot" (usually ~5th item) just to be safe.

echo "Ensuring clean state (removing Focus widget if present)..."
# Click Top Right Panel Dropdown
DISPLAY=:1 xdotool mousemove 980 140 click 1
sleep 0.5
# Click "Head Plot" (approximate location in dropdown list)
DISPLAY=:1 xdotool mousemove 980 280 click 1
sleep 0.5
# Click Bottom Right Panel Dropdown
DISPLAY=:1 xdotool mousemove 980 600 click 1
sleep 0.5
# Click "Accelerometer" or similar
DISPLAY=:1 xdotool mousemove 980 750 click 1
sleep 0.5

# Dismiss any menus/popups
DISPLAY=:1 xdotool mousemove 500 500 click 1

# 7. Verify Application is Running and Maximized
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 8. Capture Initial State
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="