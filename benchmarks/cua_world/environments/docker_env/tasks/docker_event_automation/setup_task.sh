#!/bin/bash
set -e
echo "=== Setting up Docker Event Automation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Ensure Docker is ready
wait_for_docker

# 2. Install Python Docker SDK (required for the task)
echo "Installing python docker sdk..."
pip3 install docker > /dev/null 2>&1 || true

# 3. Clean up previous artifacts
rm -rf /home/ga/projects/watchdog
mkdir -p /home/ga/projects/watchdog
chown -R ga:ga /home/ga/projects/watchdog

# 4. Clean up container if it exists
docker rm -f payment-gateway 2>/dev/null || true

# 5. Start the target container
# We use a simple alpine container that sleeps forever.
# It will exit with 137 if 'docker kill' is used, satisfying the "exit code > 0" requirement.
echo "Starting payment-gateway container..."
docker run -d --name payment-gateway alpine:3.18 sleep infinity

# 6. Record task start timestamp (for event filtering later)
date +%s > /tmp/task_start_timestamp

# 7. Create a README/hint file for the agent
cat > /home/ga/projects/watchdog/README.txt <<EOF
Task: Docker Event Watchdog
---------------------------
Target Container: payment-gateway

Goal:
1. Write 'watchdog.py' to monitor 'die' events.
2. Restart container on failure.
3. Log restarts to 'watchdog.log'.
4. Stop restarting if 3 failures occur in 60s (Circuit Breaker).
5. Write 'CRITICAL: Flapping detected' to 'alert.txt' when circuit breaker trips.

Testing:
Run your script, then use 'docker kill payment-gateway' in another terminal to simulate crashes.
EOF
chown ga:ga /home/ga/projects/watchdog/README.txt

# 8. Open a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/watchdog && ls -l; echo \"Environment ready.\"; exec bash'" > /tmp/terminal_launch.log 2>&1 &
sleep 2

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="