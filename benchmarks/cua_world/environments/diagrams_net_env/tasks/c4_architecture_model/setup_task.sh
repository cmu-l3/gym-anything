#!/bin/bash
# Setup script for c4_architecture_model task

echo "=== Setting up C4 Architecture Model Task ==="

take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output" 2>/dev/null || DISPLAY=:1 import -window root "$output" 2>/dev/null || true
}

su - ga -c "mkdir -p /home/ga/Diagrams /home/ga/Desktop" 2>/dev/null || true

# Copy system spec
cp /workspace/tasks/c4_architecture_model/data/system_spec.txt \
   /home/ga/Desktop/system_spec.txt
chown ga:ga /home/ga/Desktop/system_spec.txt 2>/dev/null || true
chmod 644 /home/ga/Desktop/system_spec.txt 2>/dev/null || true

# Remove any previous output
rm -f /home/ga/Diagrams/ecommerce_c4_model.drawio /home/ga/Diagrams/ecommerce_c4_model.pdf 2>/dev/null || true

# Baseline: file doesn't exist
echo "0" > /tmp/initial_shape_count
echo "0" > /tmp/initial_page_count
echo "file_not_exist" > /tmp/initial_c4_state

date +%s > /tmp/task_start_timestamp

pkill -f drawio 2>/dev/null || true
pkill -f "draw.io" 2>/dev/null || true
sleep 2

# Launch draw.io (agent creates new file from scratch)
su - ga -c "DISPLAY=:1 drawio" &
sleep 5

for i in $(seq 1 20); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.2
    DISPLAY=:1 xdotool mousemove 960 580 click 1 2>/dev/null || true
    sleep 0.3
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "drawio\|diagrams"; then
        break
    fi
    sleep 0.5
done

for i in $(seq 1 5); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
done

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: C4 Architecture Model for eShopOnContainers (Microsoft reference app)"
echo "System spec: /home/ga/Desktop/system_spec.txt"
echo "Expected output: /home/ga/Diagrams/ecommerce_c4_model.drawio"
