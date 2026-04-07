#!/bin/bash
echo "=== Setting up whisper_retention_policy_optimization task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_time

# Ensure Graphite is fully running and populated
ensure_graphite_ready_for_task 120

# Make sure the metrics we care about exist by feeding a couple of guaranteed data points
# Numenta benchmark data is already fed by the env startup, but we ensure the directories exist
echo "Ensuring web traffic metrics exist..."
docker exec graphite bash -c "echo 'servers.web_traffic.speed_sensor_1 100 \$(date +%s)' | nc localhost 2003"
docker exec graphite bash -c "echo 'servers.web_traffic.speed_sensor_2 100 \$(date +%s)' | nc localhost 2003"

# Wait a few seconds for Carbon to create the .wsp files and index them
sleep 5

# Verify the .wsp files actually exist inside the container
FILE_1_EXISTS=$(docker exec graphite bash -c "test -f /opt/graphite/storage/whisper/servers/web_traffic/speed_sensor_1.wsp && echo 'yes' || echo 'no'")
if [ "$FILE_1_EXISTS" = "yes" ]; then
    echo "speed_sensor_1.wsp verified."
else
    echo "WARNING: speed_sensor_1.wsp not found!"
fi

# Clean up any leftover result files from previous runs
rm -f /tmp/whisper_task_result.json 2>/dev/null || true
rm -f /tmp/storage-schemas.conf.txt 2>/dev/null || true

# Start a terminal for the agent since this is heavily CLI-based
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take an initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="