#!/bin/bash
# setup_task.sh — Proprietary App Script Monitor Config
# Prepares the environment by creating the custom script, status log, and waiting for OpManager.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Proprietary App Script Monitor Task ==="

# ------------------------------------------------------------
# 1. Create target script and log file
# ------------------------------------------------------------
echo "[setup] Creating custom monitor script and log..."

mkdir -p /opt/custom_monitors
cat > /opt/custom_monitors/check_transcode_queue.sh << 'EOF'
#!/bin/bash
# Returns the current transcode queue length
if [ -f /var/log/transcoder/status.log ]; then
    cat /var/log/transcoder/status.log
else
    echo 0
fi
EOF
chmod +x /opt/custom_monitors/check_transcode_queue.sh

mkdir -p /var/log/transcoder
echo 42 > /var/log/transcoder/status.log

# Ensure the 'ga' user owns these files so they can be read/executed if tested
chown -R ga:ga /opt/custom_monitors /var/log/transcoder

# ------------------------------------------------------------
# 2. Wait for OpManager to be ready
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/script_monitor_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/script_monitor_setup_screenshot.png" || true

echo "[setup] === Proprietary App Script Monitor Task Setup Complete ==="