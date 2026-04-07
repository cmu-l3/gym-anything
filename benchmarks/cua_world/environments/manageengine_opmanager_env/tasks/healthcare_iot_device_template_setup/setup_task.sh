#!/bin/bash
# setup_task.sh — Healthcare IoT Device Template Configuration
# Writes the specification document to the desktop and prepares OpManager.

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
# Write gateway specification to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/gateway_specs.txt" << 'SPEC_EOF'
MedTech Vitals Gateway - Monitoring Specification
===============================================

1. Custom Service Monitor
   - Service Name: HL7-Listener
   - Protocol: TCP
   - Port: 2575

2. Device Template
   - Template Name: MedTech-Vitals-Gateway
   - Vendor: Generic (or Net-SNMP)
   - Category: Server (or Unknown)
   - System OID (SysOID): .1.3.6.1.4.1.55555.1

3. Association
   - Ensure the 'HL7-Listener' service monitor is added to the associated monitors list for the 'MedTech-Vitals-Gateway' template.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/gateway_specs.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification written to $DESKTOP_DIR/gateway_specs.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/healthcare_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/healthcare_iot_setup_screenshot.png" || true

echo "[setup] healthcare_iot_device_template_setup complete."