#!/bin/bash
set -e
echo "=== Setting up task: configure_generator_runtime ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Emoncms is running
wait_for_emoncms

# 2. Get API Keys
APIKEY_WRITE=$(get_apikey_write)
echo "Using API Key: $APIKEY_WRITE"

# 3. Create Generator Simulator Script
# This runs in background to simulate a generator turning on/off
cat > /home/ga/generator_sim.py << EOF
import time
import urllib.request
import os
import sys

# Flush output immediately
sys.stdout.reconfigure(line_buffering=True)

APIKEY = "$APIKEY_WRITE"
BASE_URL = "http://localhost"

def post_status(val):
    try:
        url = f"{BASE_URL}/input/post?node=generator_room&json={{generator_status:{val}}}&apikey={APIKEY}"
        with urllib.request.urlopen(url, timeout=2) as response:
            pass
    except Exception as e:
        # Ignore transient errors during startup
        pass

print("Starting Generator Simulator...")
while True:
    # ON Phase (Running) - 20s
    for _ in range(4):
        post_status(1)
        time.sleep(5)
    # OFF Phase (Stopped) - 20s
    for _ in range(4):
        post_status(0)
        time.sleep(5)
EOF

# 4. Start Simulator in Background
nohup python3 /home/ga/generator_sim.py > /tmp/generator_sim.log 2>&1 &
SIM_PID=$!
echo "$SIM_PID" > /tmp/generator_sim.pid
echo "Simulator started with PID $SIM_PID"

# 5. Wait for input to appear in Emoncms
echo "Waiting for 'generator_status' input to appear..."
MAX_RETRIES=30
for i in $(seq 1 $MAX_RETRIES); do
    INPUT_COUNT=$(db_query "SELECT COUNT(*) FROM input WHERE name='generator_status'" 2>/dev/null || echo "0")
    if [ "$INPUT_COUNT" -gt "0" ]; then
        echo "Input detected!"
        break
    fi
    sleep 1
done

# 6. Launch Firefox to Inputs page
launch_firefox_to "http://localhost/input/view" 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="