#!/bin/bash
echo "=== Setting up add_reference_station_inventory task ==="

source /workspace/scripts/task_utils.sh

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create required directories
mkdir -p /home/ga/seiscomp/var/lib/inventory
mkdir -p /home/ga/seiscomp/etc/inventory
mkdir -p /home/ga/seiscomp/etc/key

# Clean up any existing state to ensure a clean task start
rm -f /home/ga/seiscomp/var/lib/inventory/iu_ctao_station.xml
rm -f /home/ga/seiscomp/var/lib/inventory/iu_ctao_station.scml
rm -f /home/ga/seiscomp/etc/inventory/iu_ctao_station.xml
rm -f /home/ga/seiscomp/etc/key/station_IU_CTAO

# Remove station from database if it exists
mysql -u sysop -psysop seiscomp -e "DELETE FROM Station WHERE code='CTAO';" 2>/dev/null || true

# Download real StationXML data from IRIS FDSN WS
echo "Downloading IU.CTAO StationXML from IRIS..."
curl -s --retry 3 --retry-delay 2 "https://service.iris.edu/fdsnws/station/1/query?net=IU&sta=CTAO&level=channel&format=xml" -o /home/ga/seiscomp/var/lib/inventory/iu_ctao_station.xml

if [ ! -s "/home/ga/seiscomp/var/lib/inventory/iu_ctao_station.xml" ]; then
    echo "ERROR: Failed to download StationXML data."
    exit 1
fi

chown -R ga:ga /home/ga/seiscomp/var/lib/inventory

# Record initial station count in database
INITIAL_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Station;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial station count: $INITIAL_COUNT"

# Launch terminal for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Maximize and focus terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="