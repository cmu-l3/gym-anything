#!/bin/bash
# setup_task.sh — Proprietary Telemetry Script Template Setup

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=120
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] ERROR: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Write monitoring spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/script_monitor_spec.txt" << 'SPEC_EOF'
Custom Telemetry Monitoring Specification
=======================================
The SRE team requires two new Script Templates to monitor proprietary applications.
Please configure these in OpManager under Settings > Monitoring > Script Templates.

TEMPLATE 1: Billing Queue Monitor
---------------------------------
Template Name: Billing_Queue_Depth
Script Path / Command: /opt/custom_scripts/check_billing_queue.sh
Arguments: --host $deviceIP
Output / Match Type: Numeric
Polling Interval: 10 minutes
Thresholds:
  - Warning if value > 3000
  - Critical if value > 5000

TEMPLATE 2: DRM License Monitor
-------------------------------
Template Name: DRM_License_Status
Script Path / Command: /opt/custom_scripts/check_drm_license.py
Arguments: --ip $deviceIP
Output / Match Type: String
Thresholds:
  - Critical if output equals / matches EXPIRED

SPEC_EOF

chown ga:ga "$DESKTOP_DIR/script_monitor_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Spec file written to $DESKTOP_DIR/script_monitor_spec.txt"

# ------------------------------------------------------------
# Create dummy scripts to ensure paths are valid
# ------------------------------------------------------------
mkdir -p /opt/custom_scripts
cat > /opt/custom_scripts/check_billing_queue.sh << 'EOF'
#!/bin/bash
echo "1500"
EOF
chmod +x /opt/custom_scripts/check_billing_queue.sh

cat > /opt/custom_scripts/check_drm_license.py << 'EOF'
#!/usr/bin/env python3
print("VALID")
EOF
chmod +x /opt/custom_scripts/check_drm_license.py
chown -R ga:ga /opt/custom_scripts 2>/dev/null || true

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
if declare -f ensure_firefox_on_opmanager > /dev/null; then
    ensure_firefox_on_opmanager || true
else
    su - ga -c "DISPLAY=:1 firefox http://localhost:8060 &" || true
    sleep 5
fi

# Take an initial screenshot
take_screenshot "/tmp/proprietary_telemetry_setup_screenshot.png" || true

echo "[setup] proprietary_telemetry_script_template setup complete."