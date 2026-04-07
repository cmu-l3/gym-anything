#!/bin/bash
# setup_task.sh — External SaaS SSL Certificate Monitoring
# Waits for OpManager, records start state, writes spec document to desktop, and opens Firefox.

source /workspace/scripts/task_utils.sh

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
# Write SSL Monitoring targets policy file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/ssl_monitor_targets.txt" << 'SPEC_EOF'
SSL Certificate Monitoring Specification
Requested By: Security Operations
Date: 2024-05-10

Please configure native SSL Certificate Monitoring for the following external endpoints. 
Do NOT use standard URL/Web monitors. We need to parse the X.509 certificates to track their expiration.

Target 1:
  Hostname: api.manageengine.com
  Port: 443
  Alert Threshold: 30 days before expiration

Target 2:
  Hostname: auth.ubuntu.com
  Port: 443
  Alert Threshold: 30 days before expiration

Target 3:
  Hostname: en.wikipedia.org
  Port: 443
  Alert Threshold: 30 days before expiration

All monitors must be configured to trigger an alarm if the certificate expires in 30 days or less.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/ssl_monitor_targets.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Target specification file written to $DESKTOP_DIR/ssl_monitor_targets.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/ssl_monitor_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# Take an initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/ssl_monitor_setup_screenshot.png" || true

echo "[setup] === SSL Certificate Monitoring Task Setup Complete ==="