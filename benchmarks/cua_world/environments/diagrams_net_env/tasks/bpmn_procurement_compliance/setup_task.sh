#!/bin/bash
# Setup script for bpmn_procurement_compliance task

echo "=== Setting up BPMN Procurement Compliance Task ==="

take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output" 2>/dev/null || DISPLAY=:1 import -window root "$output" 2>/dev/null || true
}

# Ensure directories
su - ga -c "mkdir -p /home/ga/Diagrams /home/ga/Desktop" 2>/dev/null || true

# Copy starting diagram and audit checklist
cp /workspace/tasks/bpmn_procurement_compliance/data/procurement_bpmn_broken.drawio \
   /home/ga/Diagrams/procurement_process.drawio
cp /workspace/tasks/bpmn_procurement_compliance/data/bpmn_audit_checklist.txt \
   /home/ga/Desktop/bpmn_audit_checklist.txt
chown ga:ga /home/ga/Diagrams/procurement_process.drawio /home/ga/Desktop/bpmn_audit_checklist.txt 2>/dev/null || true
chmod 644 /home/ga/Diagrams/procurement_process.drawio /home/ga/Desktop/bpmn_audit_checklist.txt 2>/dev/null || true

# Remove any previous exports
rm -f /home/ga/Diagrams/procurement_process.pdf /home/ga/Diagrams/procurement_process.png 2>/dev/null || true

# Record baseline: count shapes in original broken diagram using Python
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
try:
    tree = ET.parse("/home/ga/Diagrams/procurement_process.drawio")
    root = tree.getroot()
    cells = root.findall(".//mxCell")
    shapes = [c for c in cells if c.get("vertex","0")=="1" and c.get("id","") not in ("0","1")]
    edges = [c for c in cells if c.get("edge","0")=="1"]
    with open("/tmp/initial_shape_count","w") as f: f.write(str(len(shapes)))
    with open("/tmp/initial_edge_count","w") as f: f.write(str(len(edges)))
    with open("/tmp/initial_page_count","w") as f: f.write("1")
    print(f"Baseline: {len(shapes)} shapes, {len(edges)} edges, 1 page")
except Exception as e:
    print(f"Baseline recording failed: {e}")
    open("/tmp/initial_shape_count","w").write("10")
    open("/tmp/initial_edge_count","w").write("9")
    open("/tmp/initial_page_count","w").write("1")
PYEOF

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Kill any existing draw.io
pkill -f drawio 2>/dev/null || true
pkill -f "draw.io" 2>/dev/null || true
sleep 2

# Launch draw.io with the broken BPMN
su - ga -c "DISPLAY=:1 drawio /home/ga/Diagrams/procurement_process.drawio" &
sleep 5

# Dismiss update dialog
for i in $(seq 1 20); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.2
    DISPLAY=:1 xdotool mousemove 960 580 click 1 2>/dev/null || true
    sleep 0.3
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "drawio\|diagrams\|procurement"; then
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
echo "Task: BPMN Procurement Compliance Audit"
echo "Broken diagram: /home/ga/Diagrams/procurement_process.drawio"
echo "Audit checklist: /home/ga/Desktop/bpmn_audit_checklist.txt"
