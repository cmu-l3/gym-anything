#!/bin/bash
set -e
echo "=== Setting up terminate_runaway_process task ==="

source /workspace/scripts/task_utils.sh

# 1. Create dummy scripts
mkdir -p /home/ga/scripts
cat > /home/ga/scripts/stuck_import.py << 'EOF'
#!/usr/bin/env python3
import time
import os
import signal

# Handle termination gracefully to avoid zombie processes during cleanup
def handler(signum, frame):
    exit(0)

signal.signal(signal.SIGTERM, handler)

# Burn CPU
while True:
    x = 1 + 1
EOF

cat > /home/ga/scripts/daily_report.py << 'EOF'
#!/usr/bin/env python3
import time
import signal

def handler(signum, frame):
    exit(0)

signal.signal(signal.SIGTERM, handler)

# Low resource usage
while True:
    time.sleep(1)
EOF

chmod +x /home/ga/scripts/*.py
chown -R ga:ga /home/ga/scripts

# 2. Start processes
# Check if already running and kill to reset
pkill -f "stuck_import.py" || true
pkill -f "daily_report.py" || true

echo "Starting background processes..."
# Run as ga user
su - ga -c "nohup python3 /home/ga/scripts/stuck_import.py > /dev/null 2>&1 &"
su - ga -c "nohup python3 /home/ga/scripts/daily_report.py > /dev/null 2>&1 &"

sleep 2

# 3. Capture PIDs for verification
TARGET_PID=$(pgrep -f "stuck_import.py" | head -1)
SAFE_PID=$(pgrep -f "daily_report.py" | head -1)

if [ -z "$TARGET_PID" ] || [ -z "$SAFE_PID" ]; then
    echo "ERROR: Failed to start background processes"
    exit 1
fi

echo "Target PID (stuck_import): $TARGET_PID"
echo "Safe PID (daily_report): $SAFE_PID"

# Save PIDs to a JSON file for the exporter to read
cat > /tmp/task_pids.json << EOF
{
    "target_pid": $TARGET_PID,
    "safe_pid": $SAFE_PID,
    "start_time": $(date +%s)
}
EOF

# 4. Prepare Environment (Firefox)
ensure_virtualmin_ready

# Navigate to the System information page (Dashboard)
# The user needs to find "Running Processes" under "System"
navigate_to "https://localhost:10000/"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="