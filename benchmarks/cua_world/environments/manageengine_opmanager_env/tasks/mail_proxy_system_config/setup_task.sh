#!/bin/bash
# setup_task.sh — Mail Server and Proxy Configuration
# Waits for OpManager, writes the deployment config to the desktop, and records initial state.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Mail & Proxy Config Task ==="

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
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
# 2. Write the deployment configuration to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

CONFIG_FILE="$DESKTOP_DIR/production_deployment_config.txt"

cat > "$CONFIG_FILE" << 'EOF'
======================================================
OpManager Production Deployment Configuration
======================================================
Environment: Production
Datacenter: US-East
Date: 2024-03-15

REQUIRED CONFIGURATIONS

1. SMTP Mail Server Settings
   (Required for alert delivery and scheduled reports)
   - SMTP Server Host: smtp.acme-corp.internal
   - SMTP Port: 587
   - Sender / From Email Address: opmanager-noc@acme-corp.internal
   - Enable TLS/STARTTLS: Yes
   - Enable Authentication: Yes
   - Username: opmanager-noc@acme-corp.internal
   - Password: SmtpR3lay#Secure2024

2. HTTP Proxy Server Settings
   (Required for external vendor updates and maps)
   - Enable Proxy: Yes
   - Proxy Server Host: proxy-gw.acme-corp.internal
   - Proxy Port: 3128
   - Proxy Username: opmanager-svc
   - Proxy Password: ProxyAcc3ss#2024

3. Organization Branding
   (Required for report headers and UI labeling)
   - Organization / Company / Product Display Name: ACME-Corp-NetworkOps

Ensure all settings are saved in the OpManager web interface.
EOF

chown ga:ga "$CONFIG_FILE" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Deployment configuration written to $CONFIG_FILE"

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/system_config_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/system_config_setup_screenshot.png" || true

echo "[setup] === Mail & Proxy Config Task Setup Complete ==="