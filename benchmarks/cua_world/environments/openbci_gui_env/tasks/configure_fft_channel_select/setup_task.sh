#!/bin/bash
set -e
echo "=== Setting up configure_fft_channel_select task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Launch OpenBCI GUI
# Use the warmup/launch utility from environment
echo "Launching OpenBCI GUI..."
launch_openbci

# 2. Automate 'Start Session' for Synthetic Mode
# The GUI starts at the System Control Panel.
# We need to ensure "Synthetic" is selected (default) and click "Start Session".

echo "Waiting for System Control Panel..."
sleep 5

# Coordinates for 1920x1080 resolution (approximate based on v5 UI)
# "SYNTHETIC" button is usually pre-selected on first launch.
# "START SESSION" button is large, top-left or top-center of the control panel area.
# In v5.2.2 default layout:
# - Synthetic Tab: ~ (X: 180, Y: 200)
# - Start Session Button: ~ (X: 180, Y: 600) or centered.

# Let's perform a robust startup sequence using xdotool
echo "Starting Synthetic Session..."

# Click "Synthetic" (Live is default, but Synthetic is usually the 3rd option down on the left list)
# We assume the default state usually lands on "CYTON" -> "LIVE".
# We need "CYTON" -> "SYNTHETIC" (if available) or just "SYNTHETIC" mode.
# Actually, usually it defaults to "Synthetic" if no dongle is found, or we select it.

# Click "Synthetic" button (approx coordinates)
click_at 350 350
sleep 1

# Click "Start Session" button (usually large green button)
# Location varies, but usually around (350, 600) or (960, 600) depending on layout.
# We'll try a few common spots for the "Start Session" button.
click_at 350 650
sleep 1
click_at 960 650 # Center fallback
sleep 1

# 3. Wait for Main Layout to load
echo "Waiting for data stream..."
sleep 5

# 4. Verify we are in the main view
# Check if "Time Series" text is visible on screen or use window check
# Maximize window again to be sure
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 5. Ensure FFT Widget is visible
# Default layout usually has Time Series (left) and FFT (Right) or Head Plot (Right).
# We need to ensure FFT is showing.
# If it's not the default, the agent might be confused, but usually it is.
# We will assume standard default layout.

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "OpenBCI GUI should be running with Synthetic data streaming."