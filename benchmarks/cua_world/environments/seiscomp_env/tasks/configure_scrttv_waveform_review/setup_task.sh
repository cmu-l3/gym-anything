#!/bin/bash
echo "=== Setting up configure_scrttv_waveform_review task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP messaging is running
ensure_scmaster_running

# Kill any existing scrttv or scconfig instances
kill_seiscomp_gui scrttv
kill_seiscomp_gui scconfig

# Ensure a clean state by removing any previous custom scrttv configs
rm -f /home/ga/seiscomp/etc/scrttv.cfg
rm -f /home/ga/.seiscomp/scrttv.cfg
rm -f /home/ga/scrttv_screenshot.png

# Take initial screenshot of clean desktop
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="