#!/bin/bash
echo "=== Setting up compute_station_distances task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP services and MariaDB are running
systemctl start mariadb || true
sleep 2
ensure_scmaster_running

# Create Documents directory and clear any previous outputs
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/station_distances.csv
rm -f /home/ga/Documents/distance_summary.txt
chown -R ga:ga /home/ga/Documents

# Build ground truth hidden from the agent
mkdir -p /tmp/ground_truth
chmod 700 /tmp/ground_truth

echo "Building programmatic ground truth..."
python3 << 'PYEOF'
import subprocess
import json
import math
import sys

def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
    return R * 2 * math.asin(math.sqrt(a))

def run_sql(query):
    try:
        res = subprocess.run(["mysql", "-u", "sysop", "-psysop", "seiscomp", "-N", "-B", "-e", query], 
                             capture_output=True, text=True, check=True)
        return res.stdout.strip()
    except Exception as e:
        print(f"SQL Error: {e}")
        return ""

# Fetch Origin
origin_query = "SELECT latitude_value, longitude_value, depth_value, time_value FROM Origin LIMIT 1"
origin_out = run_sql(origin_query)

if not origin_out:
    print("ERROR: Could not fetch origin data.")
    sys.exit(1)

olat, olon, odep, otime = origin_out.split('\t')
olat, olon = float(olat), float(olon)

# Fetch Stations
station_query = "SELECT s.code, n.code, s.latitude, s.longitude FROM Station s INNER JOIN Network n ON s._parent_oid = n._oid WHERE n.code = 'GE'"
station_out = run_sql(station_query)

stations = []
for line in station_out.split('\n'):
    if not line.strip(): continue
    sta, net, slat, slon = line.split('\t')
    slat, slon = float(slat), float(slon)
    dist = haversine(olat, olon, slat, slon)
    stations.append({
        "station": sta, 
        "network": net, 
        "lat": slat, 
        "lon": slon, 
        "distance_km": dist
    })

# Sort by distance
stations.sort(key=lambda x: x["distance_km"])

if not stations:
    print("ERROR: Could not fetch station data.")
    sys.exit(1)

gt = {
    "origin": {
        "lat": olat, 
        "lon": olon, 
        "depth": float(odep), 
        "time": otime
    },
    "stations": stations,
    "nearest": stations[0]["station"],
    "farthest": stations[-1]["station"]
}

with open("/tmp/ground_truth/gt.json", "w") as f:
    json.dump(gt, f)
PYEOF

chmod 600 /tmp/ground_truth/gt.json

# Open a terminal for the agent to work in
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SeisComP Analysis Terminal' -e bash &" 2>/dev/null || true
sleep 3

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="