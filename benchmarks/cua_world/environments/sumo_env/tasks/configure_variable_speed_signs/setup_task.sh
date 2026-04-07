#!/bin/bash
echo "=== Setting up Configure Variable Speed Signs Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

export SUMO_HOME="/usr/share/sumo"
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"

# Clean up any potential artifacts from previous runs
rm -f "$SCENARIO_DIR/pasubio_vss.add.xml"
rm -f "$SCENARIO_DIR/tripinfos.xml"
rm -f "$SCENARIO_DIR/sumo_log.txt"

# Restore original run.sumocfg to ensure a clean starting state
cat > "$SCENARIO_DIR/run.sumocfg" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<sumoConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://sumo.dlr.de/xsd/sumoConfiguration.xsd">
    <input>
        <net-file value="pasubio_buslanes.net.xml"/>
        <route-files value="pasubio.rou.xml"/>
        <additional-files value="pasubio_vtypes.add.xml,pasubio_bus_stops.add.xml,pasubio_busses.rou.xml,pasubio_detectors.add.xml,pasubio_tls.add.xml"/>
    </input>
    <output>
        <tripinfo-output value="tripinfos.xml"/>
    </output>
    <report>
        <log value="sumo_log.txt"/>
        <no-step-log value="true"/>
    </report>
    <gui_only>
        <gui-settings-file value="settings.gui.xml"/>
    </gui_only>
</sumoConfiguration>
EOF
chown ga:ga "$SCENARIO_DIR/run.sumocfg"

# Generate briefing and hidden ground truth parameters using python
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import os
import json

scenario_dir = "/home/ga/SUMO_Scenarios/bologna_pasubio"
net_file = os.path.join(scenario_dir, "pasubio_buslanes.net.xml")

try:
    tree = ET.parse(net_file)
    root = tree.getroot()
    candidates = []
    
    # Find an appropriate real edge with multiple lanes
    for edge in root.findall('edge'):
        eid = edge.get('id', '')
        func = edge.get('function', '')
        if func == 'internal' or eid.startswith(':'):
            continue
        lanes = edge.findall('lane')
        if len(lanes) >= 2:
            lane_ids = [l.get('id') for l in lanes]
            speed = float(lanes[0].get('speed', '13.89'))
            length = float(lanes[0].get('length', '0'))
            if length > 50 and speed >= 10.0:
                candidates.append((eid, lane_ids, speed, length))
    
    candidates.sort(key=lambda x: x[3], reverse=True)
    
    # Fallback to any lane if our strict criteria weren't met
    if not candidates:
        for edge in root.findall('edge'):
            eid = edge.get('id', '')
            if edge.get('function', '') == 'internal' or eid.startswith(':'): continue
            lanes = edge.findall('lane')
            if lanes:
                lane_ids = [l.get('id') for l in lanes]
                speed = float(lanes[0].get('speed', '13.89'))
                candidates.append((eid, lane_ids, speed, float(lanes[0].get('length', '100'))))
                break

    selected = candidates[0]
except Exception as e:
    # Fail-safe absolute fallback
    selected = ("edge_fallback", ["edge_fallback_0", "edge_fallback_1"], 13.89, 100)

edge_id, lane_ids, default_speed, length = selected
reduced_speed = 8.33
lanes_str = " ".join(lane_ids)

# Write the brief
briefing = f"""=== Variable Speed Sign (VSS) Task Briefing ===

OBJECTIVE: Implement a Variable Speed Sign on the following road segment to
reduce speed during the simulated peak traffic period (timestep 300 to 900).

TARGET EDGE: {edge_id}
TARGET LANES: {lanes_str}
NUMBER OF LANES: {len(lane_ids)}

SPEED SCHEDULE (three phases):
  Step 1: time="0"   speed="{default_speed:.2f}"  (pre-peak, normal speed {default_speed*3.6:.0f} km/h)
  Step 2: time="300" speed="{reduced_speed:.2f}"  (peak period, reduced to 30 km/h)
  Step 3: time="900" speed="{default_speed:.2f}"  (post-peak, normal speed restored)

REQUIRED FILE DETAILS:
  - Create file: {scenario_dir}/pasubio_vss.add.xml
  - The root element must be <additional>
  - It must contain one <variableSpeedSign> element with:
      id="vss_peak_control"
      lanes="{lanes_str}"
  - Inside the variableSpeedSign, add three <step> elements with the
    time and speed values listed above.

CONFIGURATION UPDATE:
  - Edit {scenario_dir}/run.sumocfg
  - Append "pasubio_vss.add.xml" to the existing <additional-files> value
    (comma-separated, e.g., "...,pasubio_vss.add.xml")

RUN SIMULATION:
  - Execute: sumo -c {scenario_dir}/run.sumocfg
  - Verify tripinfos.xml is generated in the scenario directory
"""

with open(os.path.join(scenario_dir, "vss_briefing.txt"), 'w') as f:
    f.write(briefing)

# Save ground truth for verification (hidden from agent)
gt = {
    "edge_id": edge_id,
    "lanes": lanes_str,
    "default_speed": round(default_speed, 2),
    "reduced_speed": round(reduced_speed, 2)
}

with open("/tmp/vss_ground_truth.json", 'w') as f:
    json.dump(gt, f)
PYEOF

chown ga:ga "$SCENARIO_DIR/vss_briefing.txt"
chmod 644 "/tmp/vss_ground_truth.json"

# Open a terminal for the user positioned in the scenario directory
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$SCENARIO_DIR &" || \
    su - ga -c "DISPLAY=:1 xterm -geometry 100x35 -e 'cd $SCENARIO_DIR && bash' &" || true
sleep 3

# Take initial screenshot showing environment state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== VSS task setup complete ==="