#!/bin/bash
# Setup script for threat_model_stride task

echo "=== Setting up STRIDE Threat Model Task ==="

take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output" 2>/dev/null || DISPLAY=:1 import -window root "$output" 2>/dev/null || true
}

su - ga -c "mkdir -p /home/ga/Diagrams /home/ga/Desktop" 2>/dev/null || true

# Copy DFD and STRIDE reference
cp /workspace/tasks/threat_model_stride/data/oauth_dfd.drawio \
   /home/ga/Diagrams/oauth_threat_model.drawio
cp /workspace/tasks/threat_model_stride/data/stride_reference.txt \
   /home/ga/Desktop/stride_reference.txt
chown ga:ga /home/ga/Diagrams/oauth_threat_model.drawio /home/ga/Desktop/stride_reference.txt 2>/dev/null || true
chmod 644 /home/ga/Diagrams/oauth_threat_model.drawio /home/ga/Desktop/stride_reference.txt 2>/dev/null || true

# Remove any previous exports
rm -f /home/ga/Diagrams/oauth_threat_model.svg /home/ga/Diagrams/oauth_threat_model.pdf 2>/dev/null || true

# Record baseline
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
try:
    tree = ET.parse("/home/ga/Diagrams/oauth_threat_model.drawio")
    root = tree.getroot()
    cells = root.findall(".//mxCell")
    shapes = [c for c in cells if c.get("vertex","0")=="1" and c.get("id","") not in ("0","1")]
    edges = [c for c in cells if c.get("edge","0")=="1"]
    open("/tmp/initial_shape_count","w").write(str(len(shapes)))
    open("/tmp/initial_edge_count","w").write(str(len(edges)))
    open("/tmp/initial_page_count","w").write("1")
    print(f"Baseline: {len(shapes)} shapes, {len(edges)} edges")
except Exception as e:
    print(f"Baseline error: {e}")
    open("/tmp/initial_shape_count","w").write("15")
    open("/tmp/initial_page_count","w").write("1")
PYEOF

date +%s > /tmp/task_start_timestamp

pkill -f drawio 2>/dev/null || true
pkill -f "draw.io" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 drawio /home/ga/Diagrams/oauth_threat_model.drawio" &
sleep 5

for i in $(seq 1 20); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.2
    DISPLAY=:1 xdotool mousemove 960 580 click 1 2>/dev/null || true
    sleep 0.3
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "drawio\|diagrams\|oauth"; then
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
echo "Task: STRIDE Threat Model for OAuth 2.0 DFD"
echo "DFD file: /home/ga/Diagrams/oauth_threat_model.drawio"
echo "STRIDE reference: /home/ga/Desktop/stride_reference.txt"
