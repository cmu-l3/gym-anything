#!/bin/bash
# export_result.sh - Validates results and generates ground truth
echo "=== Exporting TOU Analysis Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/tou_report.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file status
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$REPORT_FILE")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Generate Ground Truth (Calculate what the answer SHOULD be)
# We run this python script using the system's access to the API/DB
cat > /tmp/generate_ground_truth.py << 'PYTHON_EOF'
import json
import urllib.request
import urllib.parse
import os
import time

# Configuration
FEED_ID_FILE = "/tmp/tou_feed_id.txt"
APIKEY = os.environ.get("EMONCMS_APIKEY_READ", "")
BASE_URL = "http://localhost"
PEAK_RATE = 0.28
OFFPEAK_RATE = 0.12
FLAT_RATE = 0.22

def get_feed_data(feed_id, start, end, interval):
    url = f"{BASE_URL}/feed/data.json?apikey={APIKEY}&id={feed_id}&start={start*1000}&end={end*1000}&interval={interval}"
    try:
        with urllib.request.urlopen(url) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        return []

def calculate_tou():
    try:
        with open(FEED_ID_FILE, 'r') as f:
            feed_id = int(f.read().strip())
    except:
        return {"error": "Feed ID file not found"}

    # Define period (last 7 days)
    end_time = int(time.time())
    start_time = end_time - (7 * 24 * 3600)
    
    # Fetch data (interval=900s matching our seed resolution for accuracy)
    data = get_feed_data(feed_id, start_time, end_time, 900)
    
    peak_kwh = 0.0
    offpeak_kwh = 0.0
    
    # Integration
    # Data is [time_ms, power_watts]
    # Energy (kWh) = Power (W) * Time (h) / 1000
    # Step is 900s = 0.25h
    
    # Basic Riemann sum
    step_hours = 900.0 / 3600.0
    
    for point in data:
        if not point or point[1] is None:
            continue
            
        ts_ms = point[0]
        power = float(point[1])
        
        # Determine hour of day (UTC/Local as per system)
        # TS is unix timestamp (UTC). Emoncms assumes browser time usually, 
        # but for backend calc we use timestamp directly.
        # Task said: Peak 07:00-22:00
        
        ts_sec = ts_ms / 1000
        hour = (int(ts_sec) % 86400) // 3600
        
        energy = (power * step_hours) / 1000.0
        
        if 7 <= hour < 22:
            peak_kwh += energy
        else:
            offpeak_kwh += energy
            
    total_kwh = peak_kwh + offpeak_kwh
    peak_cost = peak_kwh * PEAK_RATE
    offpeak_cost = offpeak_kwh * OFFPEAK_RATE
    total_cost = peak_cost + offpeak_cost
    flat_cost = total_kwh * FLAT_RATE
    savings = flat_cost - total_cost
    
    return {
        "ground_truth_feed_id": feed_id,
        "ground_truth_peak_kwh": round(peak_kwh, 2),
        "ground_truth_offpeak_kwh": round(offpeak_kwh, 2),
        "ground_truth_total_kwh": round(total_kwh, 2),
        "ground_truth_total_cost": round(total_cost, 2),
        "ground_truth_savings": round(savings, 2)
    }

print(json.dumps(calculate_tou()))
PYTHON_EOF

# Load API Key for the script
if [ -f /home/ga/emoncms_apikeys.sh ]; then
    source /home/ga/emoncms_apikeys.sh
fi

GROUND_TRUTH_JSON=$(python3 /tmp/generate_ground_truth.py)

# 4. Construct Final Result JSON
# We bundle everything into one JSON for the host-side verifier
# Use Python to safely merge JSONs
cat > /tmp/merge_results.py << PYTHON_EOF
import json
import os

try:
    with open("$REPORT_FILE", "r") as f:
        agent_report = json.load(f)
except:
    agent_report = {}

try:
    ground_truth = json.loads('$GROUND_TRUTH_JSON')
except:
    ground_truth = {}

result = {
    "output_exists": "$OUTPUT_EXISTS" == "true",
    "output_created_during_task": "$OUTPUT_CREATED_DURING_TASK" == "true",
    "output_size": int("$OUTPUT_SIZE"),
    "agent_report": agent_report,
    "ground_truth": ground_truth,
    "task_start_ts": $TASK_START
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
PYTHON_EOF

python3 /tmp/merge_results.py

# Clean up permissions so host can copy
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="