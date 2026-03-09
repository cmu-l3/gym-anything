#!/bin/bash
set -e
echo "=== Setting up Sudoku Puzzle Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing GCompris instance
kill_gcompris

# --- Clean State Setup ---
# Reset GCompris configuration and progress to ensure clean start
# We want the agent to start fresh, so we clear local share data
rm -rf /home/ga/.local/share/GCompris/sudoku 2>/dev/null || true
mkdir -p /home/ga/.config/gcompris-qt

# Write config: Windowed mode (critical for agent), no audio, no intro
cat > /home/ga/.config/gcompris-qt/gcompris-qt.conf << 'EOF'
[General]
fullscreen=false
isFirstRun=false
enableAudio=false
showLockAtStart=false
filterLevelMin=1
filterLevelMax=6
EOF
chown -R ga:ga /home/ga/.config/gcompris-qt
chown -R ga:ga /home/ga/.local/share/GCompris 2>/dev/null || true

# --- Launch Application ---
echo "Launching GCompris..."
launch_gcompris
sleep 5

# Maximize the window using wmctrl
maximize_gcompris
sleep 2

# Dismiss any potential dialogs (sometimes appear on first launch)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="
echo "GCompris is running at Main Menu."