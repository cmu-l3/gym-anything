#!/bin/bash
# setup_task.sh — Broadcast Interface Template Tuning
# Writes the tuning specification to the desktop and prepares OpManager.

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

# Write the tuning specification to the desktop
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/broadcast_interface_spec.txt" << 'SPEC_EOF'
BROADCAST INTERFACE TUNING SPECIFICATION
=========================================
Environment: Production SMPTE 2110 Media Network

1. Modify Existing Template:
   Target Template: GigabitEthernet
   New Rx Utilization Critical Threshold: 90
   New Tx Utilization Critical Threshold: 90

2. Create New Template:
   Interface Type / Name: Broadcast-Video-Tunnel
   Description: SMPTE-2110-Transport
   Rx Utilization Critical Threshold: 95
   Tx Utilization Critical Threshold: 95
   Errors / Discards Critical Threshold: 1

Note: Default templates typically alert at 70% or 80%. Broadcast streams run near line-rate.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/broadcast_interface_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Tuning specification written to $DESKTOP_DIR/broadcast_interface_spec.txt"

# Record task start timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/interface_tuning_task_start.txt
echo "[setup] Task start time recorded."

# Ensure Firefox is open on OpManager dashboard
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/interface_tuning_setup_screenshot.png" || true

echo "[setup] broadcast_interface_template_tuning setup complete."