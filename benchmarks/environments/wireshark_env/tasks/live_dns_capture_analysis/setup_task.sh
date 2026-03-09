#!/bin/bash
set -e
echo "=== Setting up live DNS capture task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (critical for anti-gaming timestamp check)
date +%s > /tmp/task_start_time.txt

# Ensure network connectivity (needed for live DNS resolution)
echo "Checking network connectivity..."
if ! ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
    echo "WARNING: No network connectivity detected"
fi

# Verify DNS resolution works locally
echo "Verifying DNS resolution..."
if ! host example.com > /dev/null 2>&1; then
    echo "WARNING: DNS resolution may not be working"
fi

# Clean up any previous task artifacts
rm -f /home/ga/Documents/captures/live_dns_capture.pcapng 2>/dev/null || true
rm -f /home/ga/Documents/captures/live_dns_capture.pcap 2>/dev/null || true
rm -f /home/ga/Documents/captures/dns_analysis_report.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure captures directory exists
mkdir -p /home/ga/Documents/captures
chown ga:ga /home/ga/Documents/captures

# Kill any stale tshark/tcpdump/wireshark processes
pkill -f tshark 2>/dev/null || true
pkill -f tcpdump 2>/dev/null || true
pkill -f wireshark 2>/dev/null || true
sleep 2

# Start Wireshark minimized/backgrounded just to have the app available
# The agent might choose to use CLI tools, so we don't force focus immediately
# But per "Initial State" requirements, app should be ready.
if ! pgrep -f "wireshark" > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark &" 2>/dev/null || true
    sleep 5
fi

# Wait for Wireshark window
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "wireshark|the wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize Wireshark
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Live DNS capture task setup complete ==="