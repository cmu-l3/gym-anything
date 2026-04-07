#!/bin/bash
set -e

echo "=== Setting up Fix Climate Data Parser Task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/climate_parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# ─────────────────────────────────────────────────────────────
# 1. Generate Realistic NOAA ISD Fixed-Width Data
# ─────────────────────────────────────────────────────────────
echo "Generating synthetic NOAA climate dataset..."
cat > /tmp/generate_data.py << 'EOF'
import math
from datetime import datetime, timedelta

def generate_file(filepath, lat, lon, station_id):
    with open(filepath, "w") as f:
        start = datetime(2023, 1, 1)
        for i in range(365 * 24):
            dt = start + timedelta(hours=i)
            # Simulate seasonal and diurnal temperature curve
            day = dt.timetuple().tm_yday
            temp_c = 10 + 15 * math.sin((day - 100) / 365.0 * 2 * math.pi) + 5 * math.sin((dt.hour - 6) / 24.0 * 2 * math.pi)
            
            # Simulate 5% missing data (NOAA sentinel: +9999)
            if (i % 20) == 0:
                temp_str = "+9999"
            else:
                temp_str = f"{int(temp_c * 10):+05d}"
            
            # NOAA ISD format mock:
            # 0-14: Station
            # 15-26: Date
            # 28-34: Lat
            # 35-42: Lon
            # 87-92: Temp (+TTTT)
            prefix = f"{station_id:<15}{dt.strftime('%Y%m%d%H%M')} {lat:+07.3f} {lon:+08.3f}"
            padded = prefix.ljust(87, 'X')
            line = f"{padded}{temp_str}XXXXX\n"
            f.write(line)

# Generate Boston data (Visible to agent)
generate_file("/home/ga/workspace/climate_parser/data/kbos_2023.txt", 42.360, -71.058, "725090-14739")
EOF
python3 /tmp/generate_data.py

# ─────────────────────────────────────────────────────────────
# 2. Populate buggy workspace files
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/parser/__init__.py" << 'EOF'
# Init
EOF

cat > "$WORKSPACE_DIR/parser/isd_parser.py" << 'EOF'
"""Module for parsing fixed-width NOAA ISD format."""

def parse_temperature(line: str) -> float:
    """
    Extracts and formats the temperature from an ISD fixed-width line.
    Temperature is 5 characters long and includes a sign (e.g., '+0125').
    It is scaled by a factor of 10 in the raw data.
    """
    # Extract temperature string
    temp_str = line[88:92]
    
    # Convert to float
    temp = float(temp_str)
    
    return temp

def parse_coordinates(line: str):
    """Extracts latitude and longitude."""
    lat = float(line[28:35])
    lon = float(line[35:43])
    return lat, lon

def get_raw_temp_string(line: str) -> str:
    """Helper used for quality control checks."""
    return line[87:92]
EOF

cat > "$WORKSPACE_DIR/parser/quality_control.py" << 'EOF'
"""Quality control and filtering rules."""

def is_valid_temperature(temp_str: str) -> bool:
    """Check if the temperature string is the NOAA missing data sentinel."""
    if temp_str == '999':
        return False
    return True

def is_in_new_england(lat: float, lon: float) -> bool:
    """Filter for stations within the New England bounding box."""
    # Approx New England bounding box: Lat 41.0 to 47.5, Lon -73.5 to -66.9
    if (lat >= 41.0 or lat <= 47.5) and (lon >= -73.5 or lon <= -66.9):
        return True
    return False
EOF

cat > "$WORKSPACE_DIR/parser/metrics.py" << 'EOF'
"""Metrics and statistical aggregations."""

def calculate_daily_average(temps: list) -> float:
    """Calculate the average temperature for a set of valid observations."""
    if not temps:
        return 0.0
    
    # Calculate average
    avg = sum(temps) / 24.0
    return avg
EOF

cat > "$WORKSPACE_DIR/run_analysis.py" << 'EOF'
from parser.isd_parser import parse_temperature, parse_coordinates, get_raw_temp_string
from parser.quality_control import is_valid_temperature, is_in_new_england
from parser.metrics import calculate_daily_average

def main():
    print("Running climate pipeline for New England...")
    valid_temps = []
    
    with open('data/kbos_2023.txt', 'r') as f:
        for line in f:
            if len(line) < 92: 
                continue
                
            lat, lon = parse_coordinates(line)
            if not is_in_new_england(lat, lon):
                continue
                
            raw_temp = get_raw_temp_string(line)
            if not is_valid_temperature(raw_temp):
                continue
                
            temp = parse_temperature(line)
            valid_temps.append(temp)
            
    if valid_temps:
        avg = calculate_daily_average(valid_temps)
        print(f"Average New England Temperature: {avg:.2f} C")
    else:
        print("No valid temperature data found.")

if __name__ == "__main__":
    main()
EOF

cat > "$WORKSPACE_DIR/tests/test_parser.py" << 'EOF'
import pytest
from parser.isd_parser import parse_temperature
from parser.quality_control import is_valid_temperature, is_in_new_england
from parser.metrics import calculate_daily_average

def test_parse_temperature_negative_sign():
    line = "X" * 87 + "-0125" + "XXX"
    assert parse_temperature(line) == -12.5

def test_parse_temperature_scaling_factor():
    line = "X" * 87 + "+0250" + "XXX"
    assert parse_temperature(line) == 25.0

def test_is_valid_temperature_sentinel():
    assert is_valid_temperature("+9999") == False
    assert is_valid_temperature("+0125") == True

def test_is_in_new_england_bounding_box():
    # Boston (In NE)
    assert is_in_new_england(42.36, -71.05) == True
    # Miami (Not in NE)
    assert is_in_new_england(25.76, -80.19) == False

def test_calculate_daily_average_incomplete():
    # Only 3 valid readings
    temps = [10.0, 10.0, 10.0] 
    assert calculate_daily_average(temps) == 10.0
EOF

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 3. Hidden Evaluation Script
# ─────────────────────────────────────────────────────────────
sudo mkdir -p /var/lib/app/ground_truth_eval
cat > /var/lib/app/ground_truth_eval/eval_tests.py << 'EOF'
import sys
import json
import traceback

workspace = sys.argv[1]
sys.path.insert(0, workspace)

results = {
    "bug1_sign": False,
    "bug2_scale": False,
    "bug3_sentinel": False,
    "bug4_bbox": False,
    "bug5_avg": False,
    "errors": []
}

try:
    from parser.isd_parser import parse_temperature
    from parser.quality_control import is_valid_temperature, is_in_new_england
    from parser.metrics import calculate_daily_average

    # Test Bug 1 & 2
    try:
        val1 = parse_temperature("X" * 87 + "-0225" + "XXX")
        val2 = parse_temperature("X" * 87 + "+0350" + "XXX")
        if val1 == -22.5:
            results["bug1_sign"] = True
            results["bug2_scale"] = True
        elif val1 == -225.0:
            results["bug1_sign"] = True
        elif val1 == 22.5:
            results["bug2_scale"] = True

        if val2 == 35.0:
            results["bug2_scale"] = True
    except Exception as e:
        results["errors"].append(f"parse_temperature error: {e}")

    # Test Bug 3
    try:
        if not is_valid_temperature("+9999") and is_valid_temperature("+0125"):
            results["bug3_sentinel"] = True
    except Exception as e:
        results["errors"].append(f"is_valid_temperature error: {e}")

    # Test Bug 4
    try:
        in_ne = is_in_new_england(42.0, -71.0)
        out_lon = is_in_new_england(42.0, -80.0)
        out_lat = is_in_new_england(30.0, -71.0)

        if in_ne and not out_lon and not out_lat:
            results["bug4_bbox"] = True
    except Exception as e:
        results["errors"].append(f"is_in_new_england error: {e}")

    # Test Bug 5
    try:
        avg = calculate_daily_average([10.0, 20.0])
        if avg == 15.0:
            results["bug5_avg"] = True
    except Exception as e:
        results["errors"].append(f"calculate_daily_average error: {e}")

except Exception as e:
    results["errors"].append(f"Import error: {e}")

with open("/tmp/eval_results.json", "w") as f:
    json.dump(results, f)
EOF
chmod 700 /var/lib/app/ground_truth_eval
chmod 600 /var/lib/app/ground_truth_eval/eval_tests.py

# ─────────────────────────────────────────────────────────────
# 4. Launch VSCode
# ─────────────────────────────────────────────────────────────
pkill -f "code" || true
sleep 1
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
sleep 5

# Focus and Maximize VSCode
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="