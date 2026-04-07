#!/bin/bash
echo "=== Setting up network_graph_centrality task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create and clean output directory
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/analyze_centrality.py
rm -f /home/ga/SUMO_Output/node_centrality.csv
rm -f /home/ga/SUMO_Output/top_5_critical_nodes.txt
chown -R ga:ga /home/ga/SUMO_Output

# Make sure standard networkx is available for the agent just in case
pip3 install networkx pandas > /dev/null 2>&1 || true

# Launch a terminal for the user to work in
echo "Launching terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio --maximize &"

# Wait for terminal window to appear
sleep 3
wait_for_window "Terminal\|ga@ubuntu" 20
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="