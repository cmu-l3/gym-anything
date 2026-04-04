#!/bin/bash
# Setup script for derive_power_factor task

source /workspace/scripts/task_utils.sh

echo "=== Setting up derive_power_factor task ==="

# 1. Start Emoncms and wait for it
wait_for_emoncms

# 2. Generate simulation script
cat > /workspace/scripts/simulate_motor.py << 'EOF'
import time
import random
import requests
import json
import sys
import os

# Configuration
EMONCMS_URL = "http://localhost"
APIKEY = os.environ.get("EMONCMS_APIKEY_WRITE")
NODE = "Compressor"

def post_data(data):
    try:
        url = f"{EMONCMS_URL}/input/post"
        payload = {
            "node": NODE,
            "fulljson": json.dumps(data),
            "apikey": APIKEY
        }
        r = requests.post(url, data=payload, timeout=2)
        return r.status_code == 200
    except Exception as e:
        return False

print(f"Starting motor simulation on node {NODE}...")

# Simulation loop
while True:
    try:
        # Generate realistic values
        # Voltage: 240V +/- 5V noise
        voltage = 240.0 + random.uniform(-5.0, 5.0)
        
        # Load profile: fluctuating around 12A
        current = 12.0 + random.uniform(-1.0, 2.0)
        
        # Power Factor: ~0.85
        pf = 0.85 + random.uniform(-0.02, 0.02)
        
        # Real Power (W) = V * I * PF
        power = voltage * current * pf
        
        data = {
            "motor_voltage_V": round(voltage, 2),
            "motor_current_A": round(current, 2),
            "motor_power_W": round(power, 2)
        }
        
        post_data(data)
        time.sleep(5)
        
    except KeyboardInterrupt:
        break
    except Exception as e:
        print(f"Error: {e}")
        time.sleep(5)
EOF

# 3. Get API Key and Start Simulation
APIKEY=$(get_apikey_write)
export EMONCMS_APIKEY_WRITE="$APIKEY"

# Kill any existing simulation
pkill -f "simulate_motor.py" || true

# Start simulation in background
nohup python3 /workspace/scripts/simulate_motor.py > /tmp/motor_sim.log 2>&1 &
echo "Motor simulation started with PID $!"

# 4. Wait for inputs to appear
echo "Waiting for inputs to be created..."
for i in {1..10}; do
    INPUTS=$(curl -s "${EMONCMS_URL}/input/list.json?apikey=${APIKEY}")
    if echo "$INPUTS" | grep -q "motor_power_W"; then
        echo "Inputs created successfully."
        break
    fi
    sleep 2
done

# 5. Clean up any existing feeds or process lists (Idempotency)
# Check for existing feed "motor_PF"
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='motor_PF'" 2>/dev/null | head -1)
if [ -n "$FEED_ID" ]; then
    echo "Deleting stale 'motor_PF' feed (ID: $FEED_ID)..."
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${FEED_ID}" >/dev/null
    # Clean DB directly to be sure
    db_query "DELETE FROM feeds WHERE id=${FEED_ID}"
fi

# Clear process list for motor_power_W
POWER_INPUT_ID=$(db_query "SELECT id FROM input WHERE name='motor_power_W' AND nodeid='Compressor'" 2>/dev/null | head -1)
if [ -n "$POWER_INPUT_ID" ]; then
    echo "Clearing process list for input $POWER_INPUT_ID..."
    db_query "UPDATE input SET processList='' WHERE id=${POWER_INPUT_ID}"
fi

# 6. Launch Firefox to Inputs page
echo "Launching Firefox..."
launch_firefox_to "http://localhost/input/view" 5

# 7. Record start time
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="