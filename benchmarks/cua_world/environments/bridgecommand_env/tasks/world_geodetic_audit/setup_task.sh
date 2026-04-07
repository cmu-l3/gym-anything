#!/bin/bash
set -e
echo "=== Setting up world_geodetic_audit task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Document directory exists and is empty of target files
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/world_catalog.csv
rm -f /home/ga/Documents/geodetic_audit_report.txt
chown ga:ga /home/ga/Documents

# Ensure Bridge Command world directory is accessible
if [ ! -d "/opt/bridgecommand/World" ]; then
    echo "ERROR: World directory not found at /opt/bridgecommand/World"
    # Create a dummy world structure if missing (fallback for testing)
    mkdir -p "/opt/bridgecommand/World/Santa Catalina"
    cat > "/opt/bridgecommand/World/Santa Catalina/terrain.ini" << EOF
TerrainLat=33.20
TerrainLong=-118.60
TerrainLatExtent=0.4
TerrainLongExtent=0.5
MapWidth=2048
MapHeight=2048
SeaMaxDepth=150
EOF
    mkdir -p "/opt/bridgecommand/World/Solent"
    cat > "/opt/bridgecommand/World/Solent/terrain.ini" << EOF
TerrainLat=50.70
TerrainLong=-1.60
TerrainLatExtent=0.2
TerrainLongExtent=0.4
MapWidth=1024
MapHeight=512
SeaMaxDepth=60
EOF
fi

# Record initial file listing for debug
ls -R /opt/bridgecommand/World > /tmp/initial_world_structure.txt

# Maximize terminal for the agent
if pgrep -f "gnome-terminal" > /dev/null; then
    DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="