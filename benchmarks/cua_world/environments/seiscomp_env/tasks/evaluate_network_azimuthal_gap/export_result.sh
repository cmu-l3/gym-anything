#!/bin/bash
echo "=== Exporting azimuthal_gap_report results ==="

# Take final screenshot (for VLM evidence if needed)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract ground truth dynamically from the SeisComP MySQL database
echo "--- Fetching Ground Truth Data ---"

# 1. Fetch Noto earthquake origin
ORIGIN_SQL="SELECT latitude_value, longitude_value FROM Origin WHERE _oid = (SELECT preferredOriginID FROM Event ORDER BY _oid DESC LIMIT 1);"
ORIGIN_COORDS=$(mysql -u sysop -psysop seiscomp -N -e "$ORIGIN_SQL" 2>/dev/null || echo "")

ORIGIN_LAT=$(echo "$ORIGIN_COORDS" | awk '{print $1}')
ORIGIN_LON=$(echo "$ORIGIN_COORDS" | awk '{print $2}')

if [ -z "$ORIGIN_LAT" ]; then ORIGIN_LAT="0.0"; fi
if [ -z "$ORIGIN_LON" ]; then ORIGIN_LON="0.0"; fi

# 2. Fetch all GE network station coordinates
STA_SQL="SELECT code, latitude, longitude FROM Station WHERE _parent_oid IN (SELECT _oid FROM Network WHERE code='GE');"
mysql -u sysop -psysop seiscomp -N -e "$STA_SQL" > /tmp/stations.txt 2>/dev/null

echo "Ground Truth Origin: $ORIGIN_LAT, $ORIGIN_LON"
echo "Stations fetched: $(wc -l < /tmp/stations.txt 2>/dev/null || echo '0')"

# Build the JSON output file securely using Python (avoids shell escaping nightmares)
python3 -c '
import json, os, sys

# Paths
start_time_file = "/tmp/task_start_time.txt"
agent_file = "/home/ga/azimuthal_gap_report.json"
stations_file = "/tmp/stations.txt"
output_file = "/tmp/task_result.json"

# Initialize Result
result = {
    "task_start_time": 0,
    "agent_file_exists": False,
    "agent_file_mtime": 0,
    "agent_file_size": 0,
    "agent_data": None,
    "ground_truth": {
        "origin_lat": float("'"$ORIGIN_LAT"'"),
        "origin_lon": float("'"$ORIGIN_LON"'"),
        "stations": []
    }
}

# 1. Load Start Time
if os.path.exists(start_time_file):
    try:
        with open(start_time_file, "r") as f:
            result["task_start_time"] = int(f.read().strip())
    except Exception:
        pass

# 2. Load Agent Data
if os.path.exists(agent_file):
    result["agent_file_exists"] = True
    result["agent_file_mtime"] = int(os.path.getmtime(agent_file))
    result["agent_file_size"] = os.path.getsize(agent_file)
    try:
        with open(agent_file, "r") as f:
            result["agent_data"] = json.load(f)
    except Exception as e:
        result["agent_data"] = {"error": f"Invalid JSON format: {str(e)}"}

# 3. Load Ground Truth Stations
if os.path.exists(stations_file):
    try:
        with open(stations_file, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 3:
                    result["ground_truth"]["stations"].append({
                        "code": parts[0],
                        "lat": float(parts[1]),
                        "lon": float(parts[2])
                    })
    except Exception:
        pass

# Write result securely
with open(output_file, "w") as f:
    json.dump(result, f, indent=2)
'

# Secure output for copy_from_env
chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="