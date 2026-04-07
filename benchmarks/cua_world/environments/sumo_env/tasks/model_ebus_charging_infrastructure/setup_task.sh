#!/bin/bash
set -e
echo "=== Setting up ebus charging task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO instances to ensure a clean state
kill_sumo 2>/dev/null || true

# Reset the scenario files from the original workspace data
echo "Resetting Bologna Pasubio scenario..."
rm -rf /home/ga/SUMO_Scenarios/bologna_pasubio/*
cp -r /workspace/data/bologna_pasubio/* /home/ga/SUMO_Scenarios/bologna_pasubio/

# Ensure the gui settings file exists
cat > /home/ga/SUMO_Scenarios/bologna_pasubio/settings.gui.xml << 'EOF'
<gui-settings>
    <scheme name="real world"></scheme>
</gui-settings>
EOF

# Ensure run.sumocfg has the exact standard baseline configuration
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
    <gui_only>
        <gui-settings-file value="settings.gui.xml"/>
    </gui_only>
</sumoConfiguration>
EOF

# Clean output directory
rm -rf /home/ga/SUMO_Output/*

# Fix permissions
chown -R ga:ga /home/ga/SUMO_Scenarios/bologna_pasubio
chown -R ga:ga /home/ga/SUMO_Output

# Open a terminal for the user
echo "Opening terminal for agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio/ &"

# Wait for terminal to appear
sleep 3
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true
sleep 1

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="