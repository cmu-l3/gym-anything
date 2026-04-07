#!/bin/bash
echo "=== Setting up compute_corridor_emissions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
rm -rf /home/ga/SUMO_Output/* 2>/dev/null || true
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Reset Pasubio sumocfg to ensure a clean starting state without emissions
cat > /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg << 'EOF'
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
</sumoConfiguration>
EOF
chown ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg

# Open a terminal for the agent since this is a CLI-focused task
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Wait for terminal window
wait_for_window "Terminal\|terminal" 15

# Focus and maximize terminal
focus_and_maximize "Terminal\|terminal"
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="