#!/bin/bash
set -e
echo "=== Setting up fix_zombie_process_leak task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
TASK_DIR="/home/ga/zombie-debug"
mkdir -p "$TASK_DIR"

# 1. Create the legacy worker script that leaks zombies
# It runs as PID 1 and ignores child signals/waits
cat > "$TASK_DIR/worker.py" << 'EOF'
import time
import subprocess
import sys
import os
import signal

# Explicitly ignore SIGCHLD (or set to default) to ensure we don't auto-reap
# In Docker without init, PID 1 has special responsibilities it often fails at
signal.signal(signal.SIGCHLD, signal.SIG_DFL)

print(f"=== Worker started (PID {os.getpid()}) ===", flush=True)

task_count = 0

while True:
    task_count += 1
    print(f"[{task_count}] Spawning short-lived task...", flush=True)
    
    # Spawn a child process that sleeps briefly then exits
    # We intentionally do NOT call .wait() or keep a reference
    try:
        # shell=False to keep process tree clean
        subprocess.Popen(["sleep", "0.5"]) 
    except Exception as e:
        print(f"Error spawning: {e}", flush=True)
    
    # Check zombie count for logs
    try:
        # Quick check of /proc to see zombie status (for debugging logs only)
        # This simulates checking process table
        z_count = int(subprocess.getoutput("grep -c 'Z' /proc/*/status 2>/dev/null || echo 0"))
        if z_count > 0:
            print(f"    Current zombie count: {z_count}", flush=True)
    except:
        pass

    # Sleep longer than the child so it has time to exit and become a zombie
    time.sleep(2)
EOF

# 2. Create Dockerfile
# Install procps so 'ps' and 'top' work for debugging
cat > "$TASK_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
# Install procps for ps/top debugging tools
RUN apt-get update && apt-get install -y procps && rm -rf /var/lib/apt/lists/*
COPY worker.py .
# Use exec form to ensure python is PID 1 (which causes the problem)
CMD ["python", "-u", "worker.py"]
EOF

# 3. Create docker-compose.yml (MISSING init: true)
cat > "$TASK_DIR/docker-compose.yml" << 'EOF'
services:
  job-worker:
    build: .
    container_name: job-worker
    # Problem: No init process means Python (PID 1) must reap zombies, which it isn't doing.
    # Fix: Add "init: true"
    restart: unless-stopped
EOF

# Set ownership
chown -R ga:ga "$TASK_DIR"

# 4. Start the environment
echo "Starting vulnerable environment..."
cd "$TASK_DIR"
# Ensure clean state
docker compose down -v 2>/dev/null || true
docker compose up -d --build

# 5. Wait for zombies to accumulate
echo "Waiting for zombies to accumulate..."
wait_for_docker_daemon 60

# Wait until we see at least one zombie or timeout (max 20s)
for i in {1..20}; do
    ZOMBIE_COUNT=$(docker exec job-worker ps aux | grep 'Z' | grep -v grep | wc -l || echo "0")
    if [ "$ZOMBIE_COUNT" -gt "0" ]; then
        echo "Confirmed zombies are leaking (Count: $ZOMBIE_COUNT)"
        break
    fi
    echo "  Waiting for zombies... ($i)"
    sleep 1
done

# Record initial zombie count for verification comparison
docker exec job-worker ps aux | grep 'Z' | grep -v grep | wc -l > /tmp/initial_zombie_count.txt

# Open Terminal for the user
echo "Opening terminal..."
su - ga -c "gnome-terminal --working-directory=$TASK_DIR" &
sleep 2

# Maximize Docker Desktop if running (it might not be, user might use CLI)
# But we'll try to focus terminal
WID=$(DISPLAY=:1 wmctrl -l | grep -i "terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="