#!/bin/bash
echo "=== Setting up evaluate_network_bottlenecks task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/queues.xml
rm -f /home/ga/SUMO_Output/stats.xml
rm -f /home/ga/SUMO_Output/bottleneck_report.txt
chown -R ga:ga /home/ga/SUMO_Output

# =====================================================================
# GENERATE GROUND TRUTH (Hidden from agent)
# =====================================================================
echo "Generating baseline ground truth for verification..."
mkdir -p /tmp/sumo_gt
cp -r /home/ga/SUMO_Scenarios/bologna_acosta/* /tmp/sumo_gt/
chown -R ga:ga /tmp/sumo_gt

# Run simulation as 'ga' with outputs directed to the hidden folder
su - ga -c "sumo -c /tmp/sumo_gt/run.sumocfg --queue-output /tmp/sumo_gt/queues.xml --statistic-output /tmp/sumo_gt/stats.xml --no-warnings > /tmp/sumo_gt/run.log 2>&1"

# Create Python script to accurately parse the ground truth
cat > /tmp/sumo_gt/parse_gt.py << 'PYEOF'
import xml.etree.ElementTree as ET
import json

max_q_len = -1.0
max_q_lane = ""
max_q_time = -1.0

try:
    tree = ET.parse('/tmp/sumo_gt/queues.xml')
    root = tree.getroot()
    for data in root.findall('data'):
        ts = float(data.get('timestep', '0'))
        lanes = data.find('lanes')
        if lanes is not None:
            for lane in lanes.findall('lane'):
                q_len = float(lane.get('queueing_length', '0'))
                # Strictly greater to tie-break by earliest timestep implicitly
                if q_len > max_q_len:
                    max_q_len = q_len
                    max_q_lane = lane.get('id', '')
                    max_q_time = ts
except Exception as e:
    print(f"Error parsing queues: {e}")

completed = 0
avg_speed = 0.0

try:
    tree = ET.parse('/tmp/sumo_gt/stats.xml')
    root = tree.getroot()
    veh = root.find('vehicles')
    if veh is not None:
        completed = int(veh.get('completed', '0'))
    trip = root.find('vehicleTripStatistics')
    if trip is not None:
        avg_speed = float(trip.get('speed', '0'))
except Exception as e:
    print(f"Error parsing stats: {e}")

gt = {
    "max_queue_lane": max_q_lane,
    "max_queue_length": max_q_len,
    "max_queue_time": max_q_time,
    "total_vehicles_completed": completed,
    "average_vehicle_speed": avg_speed
}

with open('/root/.bologna_baseline_gt.json', 'w') as f:
    json.dump(gt, f)
PYEOF

# Execute the parse script
python3 /tmp/sumo_gt/parse_gt.py
chmod 400 /root/.bologna_baseline_gt.json

# Clean up GT working directory
rm -rf /tmp/sumo_gt

# =====================================================================
# SETUP AGENT ENVIRONMENT
# =====================================================================

# Open a terminal for the agent in the correct directory
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_acosta &"
sleep 3

# Wait for terminal window
wait_for_window "Terminal\|ga@ubuntu" 10
focus_and_maximize "Terminal\|ga@ubuntu"
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="