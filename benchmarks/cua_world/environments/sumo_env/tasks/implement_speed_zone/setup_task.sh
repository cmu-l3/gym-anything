#!/bin/bash
echo "=== Setting up implement_speed_zone task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Set environment
export SUMO_HOME="/usr/share/sumo"
export DISPLAY=:1

# Kill any running SUMO processes
kill_sumo

# Ensure working directories exist
sudo -u ga mkdir -p /home/ga/SUMO_Scenarios/zona30
sudo -u ga mkdir -p /home/ga/SUMO_Output

# Clean any previous task artifacts
rm -f /home/ga/SUMO_Scenarios/zona30/*
rm -f /home/ga/SUMO_Output/zona30_tripinfo.xml
rm -f /home/ga/SUMO_Output/zona30_summary.txt
rm -f /home/ga/SUMO_Output/baseline_tripinfo.xml

# Run baseline simulation to generate reference tripinfo
echo "Running baseline simulation..."
cd /home/ga/SUMO_Scenarios/bologna_pasubio

sumo -c run.sumocfg \
    --tripinfo-output /home/ga/SUMO_Output/baseline_tripinfo.xml \
    --no-step-log true \
    --log /tmp/baseline_sumo.log > /dev/null 2>&1

# Calculate baseline average duration for later verification
python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/home/ga/SUMO_Output/baseline_tripinfo.xml')
    durations = [float(t.get('duration', 0)) for t in tree.findall('.//tripinfo')]
    avg = sum(durations) / len(durations) if durations else 0
    print(f'{avg:.2f}')
except:
    print('0')
" > /tmp/baseline_avg_duration.txt

# Count edges <= 13.89 in original network
python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_buslanes.net.xml')
    edges_to_modify = set()
    for edge in tree.findall('.//edge'):
        eid = edge.get('id', '')
        if eid.startswith(':'): continue
        for lane in edge.findall('lane'):
            speed = float(lane.get('speed', '0'))
            if 0 < speed <= 13.89:
                edges_to_modify.add(eid)
                break
    print(len(edges_to_modify))
except:
    print('0')
" > /tmp/expected_modified_edges.txt

# Set proper ownership
chown -R ga:ga /home/ga/SUMO_Scenarios/zona30
chown -R ga:ga /home/ga/SUMO_Output

# Open a terminal for the agent
echo "Opening terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/zona30 --title='SUMO Task Terminal' -- bash -c 'echo \"=== SUMO Zona 30 Task ===\"; echo \"Working directory: /home/ga/SUMO_Scenarios/zona30\"; echo \"Pasubio network: /home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_buslanes.net.xml\"; echo \"Baseline tripinfo: /home/ga/SUMO_Output/baseline_tripinfo.xml\"; echo \"\"; exec bash'" &
sleep 3

# Focus and maximize the terminal
wait_for_window "Terminal" 10 || wait_for_window "terminal" 10 || true
focus_and_maximize "Terminal" || focus_and_maximize "terminal" || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="