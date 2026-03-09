#!/bin/bash
# Setup script for vsm_lean_analysis task

echo "=== Setting up VSM Lean Analysis Task ==="

take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output" 2>/dev/null || DISPLAY=:1 import -window root "$output" 2>/dev/null || true
}

su - ga -c "mkdir -p /home/ga/Diagrams /home/ga/Desktop" 2>/dev/null || true

# Copy production data and VSM guide
cp /workspace/tasks/vsm_lean_analysis/data/production_metrics.csv \
   /home/ga/Desktop/production_metrics.csv
cp /workspace/tasks/vsm_lean_analysis/data/vsm_guide.txt \
   /home/ga/Desktop/vsm_guide.txt
chown ga:ga /home/ga/Desktop/production_metrics.csv /home/ga/Desktop/vsm_guide.txt 2>/dev/null || true
chmod 644 /home/ga/Desktop/production_metrics.csv /home/ga/Desktop/vsm_guide.txt 2>/dev/null || true

# Remove any previous VSM output
rm -f /home/ga/Diagrams/current_state_vsm.drawio /home/ga/Diagrams/current_state_vsm.pdf 2>/dev/null || true

# Record baseline: VSM file does not exist yet
echo "0" > /tmp/initial_shape_count
echo "0" > /tmp/initial_page_count
echo "file_not_exist" > /tmp/initial_vsm_state

date +%s > /tmp/task_start_timestamp

# Kill any existing draw.io
pkill -f drawio 2>/dev/null || true
pkill -f "draw.io" 2>/dev/null || true
sleep 2

# Launch draw.io (no starting file — agent creates from scratch)
su - ga -c "DISPLAY=:1 drawio" &
sleep 5

# Dismiss any startup dialogs (update dialog and new-file dialog)
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
echo "Task: Current-State Value Stream Map"
echo "Production data: /home/ga/Desktop/production_metrics.csv"
echo "VSM guide: /home/ga/Desktop/vsm_guide.txt"
echo "Expected output: /home/ga/Diagrams/current_state_vsm.drawio"
