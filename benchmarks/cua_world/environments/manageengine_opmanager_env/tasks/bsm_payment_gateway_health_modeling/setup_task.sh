#!/bin/bash
# setup_task.sh — BSM Payment Gateway Health Modeling
# Writes the architecture spec to the desktop and prepares OpManager.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=120
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] ERROR: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        exit 1
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Write architecture specification file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/payment_gateway_bsm_spec.txt" << 'SPEC_EOF'
PAYMENT PROCESSING GATEWAY - ARCHITECTURE SPECIFICATION
Version: 1.1
Author: Infrastructure Engineering
Date: 2024-03-12

BACKGROUND:
The new Payment Processing Gateway is a critical business service consisting of
four dependent nodes. To accurately reflect SLA and reduce alert fatigue, these
must be configured in OpManager as a single "Business Service" (not a regular
Device Group).

REQUIREMENTS:

1. DEVICE PROVISIONING
Add the following four devices to the OpManager inventory:
  - Hostname: Payment-Web-01
    IP Address: 10.50.1.10

  - Hostname: Payment-Web-02
    IP Address: 10.50.1.11

  - Hostname: Payment-App-Core
    IP Address: 10.50.2.10

  - Hostname: Payment-DB-Cluster
    IP Address: 10.50.3.10

(Note: Devices may show as 'Down' or 'Unmanaged' upon discovery since they are
in a secure VLAN. This is expected behavior for this staging phase.)

2. BUSINESS SERVICE CREATION
Navigate to the Maps / Business Services section of OpManager.
Create a new Business Service with the EXACT name:
  Payment-Processing-Gateway

Add all four of the newly provisioned Payment-* devices as components/dependents
into this Business Service.

END OF SPECIFICATION
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/payment_gateway_bsm_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Architecture spec written to $DESKTOP_DIR/payment_gateway_bsm_spec.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/bsm_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/bsm_setup_screenshot.png" || true

echo "[setup] BSM Payment Gateway setup complete."