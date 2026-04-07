#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug Drone Flight Log Task ==="

WORKSPACE_DIR="/home/ga/workspace/drone_auditor"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"
cd "$WORKSPACE_DIR"

# ──────────────────────────────────────────────
# 1. Generate buggy codebase
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/config.py" << 'EOF'
# Drone Configuration Parameters
BATTERY_CELLS = 2
MAX_ALTITUDE_M = 120
MAX_VIBRATION_G = 2.5
GEOFENCE_RADIUS_M = 500
EOF

cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
import math

def haversine(lat1, lon1, lat2, lon2):
    """Calculate the great circle distance in meters between two points on earth."""
    R = 6371000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))
EOF

cat > "$WORKSPACE_DIR/geofence.py" << 'EOF'
import math
import config
# Hint: A robust distance formula is available in utils.py
from utils import haversine

def check_geofence(home_lat, home_lon, lat, lon):
    # BUG 1: Cartesian distance instead of Haversine
    dist = math.sqrt((lat - home_lat)**2 + (lon - home_lon)**2) * 111320
    return dist > config.GEOFENCE_RADIUS_M
EOF

cat > "$WORKSPACE_DIR/battery.py" << 'EOF'
import config

def check_low_battery(voltage):
    # Drones use varying cell counts. Calculate average per-cell voltage.
    # BUG 4: Hardcoded to 3 cells instead of using config.BATTERY_CELLS
    cell_voltage = voltage / 3.0
    return cell_voltage < 3.2
EOF

cat > "$WORKSPACE_DIR/parser.py" << 'EOF'
import csv
import config
from geofence import check_geofence
from battery import check_low_battery

def parse_log(filepath):
    report = {
        'geofence_breach': False,
        'altitude_breach': False,
        'max_vibration': 0.0,
        'low_battery': False,
        'duration_s': 0.0
    }

    first_ts = None
    last_ts = None
    home_lat, home_lon = 0.0, 0.0

    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = float(row['time_us'])
            if first_ts is None:
                first_ts = ts
                home_lat, home_lon = float(row['lat']), float(row['lon'])
            last_ts = ts

            # 1. Geofence
            if check_geofence(home_lat, home_lon, float(row['lat']), float(row['lon'])):
                report['geofence_breach'] = True

            # 2. Altitude 
            # BUG 2: Uses amsl (Above Mean Sea Level) instead of rel (Relative/AGL)
            if float(row['alt_amsl']) > config.MAX_ALTITUDE_M:
                report['altitude_breach'] = True

            # 3. Vibration
            # BUG 3: Uses Manhattan distance instead of RMS (Root Mean Square)
            vib_x, vib_y, vib_z = float(row['vib_x']), float(row['vib_y']), float(row['vib_z'])
            vib_mag = abs(vib_x) + abs(vib_y) + abs(vib_z)
            if vib_mag > report['max_vibration']:
                report['max_vibration'] = vib_mag

            # 4. Battery
            if check_low_battery(float(row['voltage'])):
                report['low_battery'] = True

    # 5. Duration
    # BUG 5: Uses 1000 instead of 1,000,000 for microseconds to seconds conversion
    if first_ts is not None and last_ts is not None:
        report['duration_s'] = (last_ts - first_ts) / 1000.0

    return report
EOF

cat > "$WORKSPACE_DIR/main.py" << 'EOF'
import os
import json
import glob
from parser import parse_log

def main():
    if not os.path.exists('output'):
        os.makedirs('output')

    log_files = glob.glob('data/*.csv')
    if not log_files:
        print("No CSV files found in data/")
        
    for f in log_files:
        basename = os.path.basename(f)
        try:
            report = parse_log(f)
            out_path = os.path.join('output', basename.replace('.csv', '.json'))
            with open(out_path, 'w') as out:
                json.dump(report, out, indent=2)
            print(f"Processed {basename} -> {out_path}")
        except Exception as e:
            print(f"Error processing {basename}: {e}")

if __name__ == '__main__':
    main()
EOF

# ──────────────────────────────────────────────
# 2. Generate dummy data for agent testing
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/flight_001.csv" << 'EOF'
time_us,lat,lon,alt_amsl,alt_rel,vib_x,vib_y,vib_z,voltage
0,37.7749,-122.4194,100.0,0.0,0.0,0.0,0.0,8.0
1000000,37.7749,-122.4190,125.0,25.0,1.0,1.0,1.0,7.0
EOF

# Secure permissions
chown -R ga:ga "$WORKSPACE_DIR"

# ──────────────────────────────────────────────
# 3. Launch VS Code correctly
# ──────────────────────────────────────────────
pkill -u ga -f 'code' 2>/dev/null || true
sleep 1

echo "Starting VS Code..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR > /dev/null 2>&1 &"
sleep 6

focus_vscode_window 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="