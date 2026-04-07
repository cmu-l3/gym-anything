#!/bin/bash
echo "=== Setting up implement_hgv_bottleneck_ban task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Ensure fresh output directory
rm -rf /home/ga/SUMO_Output/* 2>/dev/null || true
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"

# 1. Create truck vType definition
cat > ${WORK_DIR}/truck_vtype.add.xml << 'EOF'
<additional>
    <vType id="truck_type" vClass="truck" color="1,0,0" length="12.0" maxSpeed="20.0"/>
</additional>
EOF

# 2. Generate robust truck demand using SUMO's randomTrips.py
echo "Generating background truck demand..."
python3 $SUMO_HOME/tools/randomTrips.py \
    -n ${WORK_DIR}/acosta_buslanes.net.xml \
    -o ${WORK_DIR}/trucks.rou.xml \
    --vehicle-class truck \
    --trip-attributes 'type="truck_type"' \
    --prefix truck \
    --fringe-factor 10 \
    -p 1 \
    --end 1000 \
    --seed 42

# 3. Create baseline configuration
cat > ${WORK_DIR}/baseline.sumocfg << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<sumoConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://sumo.dlr.de/xsd/sumoConfiguration.xsd">
    <input>
        <net-file value="acosta_buslanes.net.xml"/>
        <route-files value="acosta_busses.rou.xml,trucks.rou.xml"/>
        <additional-files value="acosta_vtypes.add.xml,acosta_bus_stops.add.xml,acosta_detectors.add.xml,truck_vtype.add.xml"/>
    </input>
    <output>
        <tripinfo-output value="/home/ga/SUMO_Output/baseline_tripinfo.xml"/>
    </output>
    <time>
        <begin value="0"/>
        <end value="2000"/>
    </time>
</sumoConfiguration>
EOF

# Ensure all files are owned by the user
chown -R ga:ga ${WORK_DIR}

# Take timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="