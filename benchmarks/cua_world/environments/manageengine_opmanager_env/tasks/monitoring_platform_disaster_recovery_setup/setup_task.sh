#!/bin/bash
# setup_task.sh — Monitoring Platform Disaster Recovery Setup
# Waits for OpManager, ensures a clean state, and records the start timestamp.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Disaster Recovery Task ==="

# 1. Wait for OpManager to be ready
echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s, continuing anyway." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# 2. Ensure clean OS state (remove backup directory if it somehow exists)
echo "[setup] Ensuring clean filesystem state..."
if [ -d "/var/opt/opmanager_backups" ]; then
    sudo rm -rf "/var/opt/opmanager_backups"
    echo "[setup] Removed pre-existing /var/opt/opmanager_backups"
fi

# 3. Record task start timestamp for anti-gaming checks
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/dr_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded: $(cat /tmp/dr_task_start.txt)"

# 4. Ensure Firefox is open on OpManager dashboard
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# 5. Take initial screenshot
echo "[setup] Capturing initial state..."
sleep 1
take_screenshot "/tmp/dr_setup_screenshot.png" || true

if [ -f /tmp/dr_setup_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/dr_setup_screenshot.png 2>/dev/null || echo "0")
    echo "[setup] Initial screenshot captured: ${SIZE} bytes"
fi

echo "[setup] === Setup Complete ==="