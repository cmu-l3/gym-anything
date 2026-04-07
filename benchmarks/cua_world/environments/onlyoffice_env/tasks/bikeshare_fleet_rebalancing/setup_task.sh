#!/bin/bash
set -euo pipefail

echo "=== Setting up Bikeshare Fleet Rebalancing Task ==="

# Record task start timestamp for anti-gaming verification
echo $(date +%s) > /tmp/task_start_time.txt

# Source utils if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
    cleanup_temp_files 2>/dev/null || true
    kill_onlyoffice ga 2>/dev/null || true
fi

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

TRIPS_CSV="$WORKSPACE_DIR/cabi_weekend_trips.csv"
STATIONS_CSV="$WORKSPACE_DIR/station_directory.csv"

# Generate realistic Capital Bikeshare open data
cat > /tmp/generate_cabi_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
from datetime import datetime, timedelta

random.seed(2024)

# Realistic DC stations
stations = [
    {"id": "31258", "name": "Lincoln Memorial", "cap": 35, "type": "destination"},
    {"id": "31247", "name": "Jefferson Dr & 14th St SW", "cap": 25, "type": "destination"},
    {"id": "31101", "name": "14th & V St NW", "cap": 31, "type": "origin"},
    {"id": "31200", "name": "Massachusetts Ave & Dupont Circle NW", "cap": 45, "type": "origin"},
    {"id": "31623", "name": "Columbus Circle / Union Station", "cap": 55, "type": "balanced"},
    {"id": "31229", "name": "New Hampshire Ave & T St NW", "cap": 23, "type": "origin"},
    {"id": "31214", "name": "17th & Corcoran St NW", "cap": 15, "type": "origin"},
    {"id": "31289", "name": "Henry Bacon Dr & Lincoln Memorial Circle NW", "cap": 25, "type": "destination"},
    {"id": "31288", "name": "4th St & Madison Dr NW", "cap": 25, "type": "destination"},
    {"id": "31104", "name": "Adams Mill & Columbia Rd NW", "cap": 19, "type": "origin"},
    {"id": "31600", "name": "Edgewood Rec Center", "cap": 15, "type": "balanced"},
    {"id": "31503", "name": "Florida Ave & R St NW", "cap": 23, "type": "origin"},
    {"id": "31201", "name": "15th & P St NW", "cap": 19, "type": "balanced"},
    {"id": "31108", "name": "4th & M St SW", "cap": 23, "type": "balanced"},
    {"id": "31613", "name": "Eastern Market Metro", "cap": 19, "type": "balanced"}
]

# Add some random filler stations
for i in range(135):
    stations.append({
        "id": str(32000 + i),
        "name": f"Neighborhood Station {i}",
        "cap": random.choice([15, 19, 23, 27]),
        "type": "balanced"
    })

# Write Station Directory
with open('/home/ga/Documents/Spreadsheets/station_directory.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["station_id", "station_name", "capacity"])
    for s in stations:
        writer.writerow([s["id"], s["name"], s["cap"]])

origins = [s for s in stations if s["type"] in ["origin", "balanced"]]
destinations = [s for s in stations if s["type"] in ["destination", "balanced"]]

# Generate 5000 trips
trips = []
start_time = datetime(2024, 5, 11, 8, 0, 0) # Saturday morning

# Biased weights to ensure predictable deficit/surplus
o_weights = [10 if s["type"]=="origin" else 2 for s in origins]
d_weights = [15 if s["type"]=="destination" else 2 for s in destinations]

for i in range(5000):
    start_station = random.choices(origins, weights=o_weights)[0]
    end_station = random.choices(destinations, weights=d_weights)[0]
    
    # Avoid self-loops
    while end_station["id"] == start_station["id"]:
        end_station = random.choices(destinations, weights=d_weights)[0]
    
    duration = timedelta(minutes=random.randint(5, 45), seconds=random.randint(0, 59))
    trip_start = start_time + timedelta(minutes=random.randint(0, 48*60))
    trip_end = trip_start + duration
    
    trips.append([
        f"W24{random.randint(1000000, 9999999)}",
        trip_start.strftime("%Y-%m-%d %H:%M:%S"),
        trip_end.strftime("%Y-%m-%d %H:%M:%S"),
        start_station["name"],
        start_station["id"],
        end_station["name"],
        end_station["id"],
        random.choice(["member", "casual"])
    ])

trips.sort(key=lambda x: x[1])

with open('/home/ga/Documents/Spreadsheets/cabi_weekend_trips.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["ride_id", "started_at", "ended_at", "start_station_name", "start_station_id", "end_station_name", "end_station_id", "member_casual"])
    writer.writerows(trips)

# Calculate and save Ground Truth (hidden from agent)
departures = {}
arrivals = {}
for t in trips:
    departures[t[3]] = departures.get(t[3], 0) + 1
    arrivals[t[5]] = arrivals.get(t[5], 0) + 1

net = {}
for s in stations:
    n = s["name"]
    net[n] = arrivals.get(n, 0) - departures.get(n, 0)

import json
with open('/tmp/ground_truth.json', 'w') as f:
    json.dump({"departures": departures, "arrivals": arrivals, "net": net}, f)

PYEOF

python3 /tmp/generate_cabi_data.py
chown ga:ga "$TRIPS_CSV" "$STATIONS_CSV"

# Start ONLYOFFICE maximized
if ! pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    echo "Starting ONLYOFFICE..."
    su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell &"
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
            break
        fi
        sleep 1
    done
fi

DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="