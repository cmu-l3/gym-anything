#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: configure_daily_minmax@1 ==="

# 1. Start Emoncms and ensure it's ready
wait_for_emoncms

# 2. Get API Keys
APIKEY_WRITE=$(get_apikey_write)

# 3. Clear any previous task data (idempotency)
echo "Clearing old inputs and feeds..."
# Delete all inputs
db_query "TRUNCATE TABLE inputs;"
# Delete all feeds (and their data directories ideally, but truncating table is enough for logic check)
db_query "TRUNCATE TABLE feeds;"
# Flush Redis to remove cached values
docker exec emoncms-redis redis-cli flushall >/dev/null

# 4. Start background data generator
# This script simulates a sensor posting to Emoncms every 5 seconds
echo "Starting data generator..."
cat > /tmp/gen_temp_data.py << 'EOF'
import time
import math
import random
import urllib.request
import sys
import signal

def handler(signum, frame):
    sys.exit(0)

signal.signal(signal.SIGTERM, handler)

emoncms_url = "http://localhost"
apikey = sys.argv[1]

# Generate a day's worth of temp curve
print("Starting loop...")
while True:
    try:
        # Simulated temp: Base 20C, swing +/- 10C
        hour_sim = (time.time() / 3600.0) % 24
        temp = 20 + 10 * math.sin(math.pi * (hour_sim - 6) / 12) + random.uniform(-0.5, 0.5)
        
        # Post to Emoncms
        url = f"{emoncms_url}/input/post?node=environment&json={{greenhouse_temp:{round(temp, 2)}}}&apikey={apikey}"
        with urllib.request.urlopen(url) as response:
            pass
    except Exception as e:
        print(f"Error: {e}")
    
    time.sleep(5)
EOF

# Kill any existing generator
pkill -f "gen_temp_data.py" || true

# Start new generator in background
nohup python3 /tmp/gen_temp_data.py "$APIKEY_WRITE" > /tmp/gen_data.log 2>&1 &
GEN_PID=$!
echo "Generator started with PID $GEN_PID"

# 5. Wait for input to appear in Emoncms
echo "Waiting for input 'greenhouse_temp' to register..."
for i in {1..30}; do
    COUNT=$(db_query "SELECT COUNT(*) FROM inputs WHERE name='greenhouse_temp'")
    if [ "$COUNT" -gt "0" ]; then
        echo "Input 'greenhouse_temp' detected."
        break
    fi
    sleep 2
done

# Double check input exists
COUNT=$(db_query "SELECT COUNT(*) FROM inputs WHERE name='greenhouse_temp'")
if [ "$COUNT" -eq "0" ]; then
    echo "ERROR: Input failed to appear."
    exit 1
fi

# 6. Launch Firefox to Inputs page
echo "Launching Firefox..."
launch_firefox_to "http://localhost/input/view" 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

# 8. Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="