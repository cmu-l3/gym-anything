#!/bin/bash
# Setup script for network_topology_multi_layer task

echo "=== Setting up Network Topology Multi-Layer Task ==="

# Fallback utilities
take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output" 2>/dev/null || DISPLAY=:1 import -window root "$output" 2>/dev/null || true
}

# Ensure diagram directories exist
su - ga -c "mkdir -p /home/ga/Diagrams /home/ga/Desktop" 2>/dev/null || true

# Copy starting diagram and requirements
cp /workspace/tasks/network_topology_multi_layer/data/enterprise_network_starter.drawio \
   /home/ga/Diagrams/enterprise_network.drawio
cp /workspace/tasks/network_topology_multi_layer/data/network_requirements.txt \
   /home/ga/Desktop/network_requirements.txt
chown ga:ga /home/ga/Diagrams/enterprise_network.drawio /home/ga/Desktop/network_requirements.txt 2>/dev/null || true
chmod 644 /home/ga/Diagrams/enterprise_network.drawio /home/ga/Desktop/network_requirements.txt 2>/dev/null || true

# Remove any previous PDF output
rm -f /home/ga/Diagrams/enterprise_network.pdf 2>/dev/null || true

# Record baseline state
echo "5" > /tmp/initial_shape_count
echo "1" > /tmp/initial_page_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Start time: $(cat /tmp/task_start_timestamp)"

# Kill any existing draw.io instances
pkill -f drawio 2>/dev/null || true
pkill -f "draw.io" 2>/dev/null || true
sleep 2

# Launch draw.io with the starter file
su - ga -c "DISPLAY=:1 drawio /home/ga/Diagrams/enterprise_network.drawio" &
sleep 5

# Aggressively dismiss update dialog
for i in $(seq 1 20); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.2
    # Click Cancel button area (typical position on 1920x1080)
    DISPLAY=:1 xdotool mousemove 960 580 click 1 2>/dev/null || true
    sleep 0.3
    # Check if drawio is showing (not just dialog)
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "drawio\|diagrams\|enterprise"; then
        break
    fi
    sleep 0.5
done

# Additional Escape presses
for i in $(seq 1 5); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Enterprise Network Topology (Multi-Layer)"
echo "Starting file: /home/ga/Diagrams/enterprise_network.drawio"
echo "Requirements: /home/ga/Desktop/network_requirements.txt"
echo "Expected output PDF: /home/ga/Diagrams/enterprise_network.pdf"
