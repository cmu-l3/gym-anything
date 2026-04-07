#!/bin/bash
echo "=== Setting up Generate Spatial Context task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"

# Clean previous task outputs
rm -f "$WORK_DIR/pasubio_area.osm"
rm -f "$WORK_DIR/pasubio_polygons.add.xml"
rm -f "$WORK_DIR/run_enriched.sumocfg"

# Download real OSM data accurately corresponding to the network bounding box
echo "Downloading OSM data for the network bounding box..."
cat > /tmp/download_osm.py << 'EOF'
import sys
import os
import urllib.request

# SUMO tools path
sys.path.append('/usr/share/sumo/tools')

try:
    import sumolib
    work_dir = "/home/ga/SUMO_Scenarios/bologna_pasubio"
    net_file = os.path.join(work_dir, "pasubio_buslanes.net.xml")
    out_file = os.path.join(work_dir, "pasubio_area.osm")

    # Read the simulation network to extract the boundary
    net = sumolib.net.readNet(net_file)
    bbox = net.getBBox()

    # Convert the Cartesian BBox back into WGS84 Longitude/Latitude
    lon1, lat1 = net.convertXY2LonLat(bbox[0][0], bbox[0][1])
    lon2, lat2 = net.convertXY2LonLat(bbox[1][0], bbox[1][1])

    min_lon = min(lon1, lon2)
    min_lat = min(lat1, lat2)
    max_lon = max(lon1, lon2)
    max_lat = max(lat1, lat2)

    # Fetch corresponding data from the Overpass API
    url = f"https://overpass-api.de/api/map?bbox={min_lon},{min_lat},{max_lon},{max_lat}"
    urllib.request.urlretrieve(url, out_file)
    print(f"Downloaded OSM data to {out_file}")
except Exception as e:
    print(f"Failed to download OSM data: {e}")
    sys.exit(1)
EOF

python3 /tmp/download_osm.py

# If download failed (e.g., due to Overpass rate limits), inject a valid fallback payload
if [ ! -f "$WORK_DIR/pasubio_area.osm" ] || [ ! -s "$WORK_DIR/pasubio_area.osm" ]; then
    echo "Warning: Download failed. Injecting fallback minimal OSM file..."
    cat > "$WORK_DIR/pasubio_area.osm" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="CGImap">
 <bounds minlat="44.49" minlon="11.31" maxlat="44.51" maxlon="11.33"/>
 <node id="1" visible="true" lat="44.498" lon="11.315"/>
 <node id="2" visible="true" lat="44.499" lon="11.315"/>
 <node id="3" visible="true" lat="44.499" lon="11.316"/>
 <node id="4" visible="true" lat="44.498" lon="11.316"/>
 <way id="10" visible="true">
  <nd ref="1"/><nd ref="2"/><nd ref="3"/><nd ref="4"/><nd ref="1"/>
  <tag k="building" v="yes"/>
 </way>
 <way id="11" visible="true">
  <nd ref="1"/><nd ref="3"/>
  <tag k="natural" v="water"/>
 </way>
</osm>
EOF
fi

chown ga:ga "$WORK_DIR/pasubio_area.osm"

# Start the agent with an open terminal sitting at the correct context
if command -v gnome-terminal &> /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$WORK_DIR &"
else
    su - ga -c "DISPLAY=:1 xterm -e 'cd $WORK_DIR && bash' &"
fi

sleep 3

# Maximize the terminal frame
focus_and_maximize "Terminal\|xterm"

# Capture evidence of task kickoff
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="