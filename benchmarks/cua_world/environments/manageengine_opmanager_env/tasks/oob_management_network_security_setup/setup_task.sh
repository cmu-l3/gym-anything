#!/bin/bash
# setup_task.sh — OOB Management Network Security Setup
# Prepares the OpManager environment, creates the security spec document.

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
# Write the Security Spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/oob_security_spec.txt" << 'SPEC_EOF'
OOB Management Network Security Specification
Document ID: SEC-ARCH-992
Effective Date: 2024-05-01

SECTION 1: PROXY SERVER CONFIGURATION
---------------------------------------
OpManager must route external traffic through the secure OOB proxy.
Navigate to Proxy Server Settings and configure:

  Proxy Server IP : 10.255.10.50
  Proxy Port      : 3128
  Requires Auth   : Yes
  Username        : svc_nms_proxy
  Password        : ProxySecure99!
  No Proxy For    : 127.0.0.1, localhost, *.corp.local, 10.0.0.0/8

SECTION 2: RADIUS AUTHENTICATION CONFIGURATION
------------------------------------------------
Local accounts are prohibited. Enable RADIUS Authentication
and configure the primary and secondary servers exactly as follows:

  Primary Server IP   : 172.16.100.10
  Authentication Port : 1812
  Protocol            : MSCHAPv2
  Shared Secret       : RadAuth#2024!

  Secondary Server IP : 172.16.100.11
  Authentication Port : 1812
  Protocol            : MSCHAPv2
  Shared Secret       : RadAuth#2024!

Ensure all changes are saved and applied.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/oob_security_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] OOB security spec written to $DESKTOP_DIR/oob_security_spec.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/oob_security_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/oob_security_setup_screenshot.png" || true

echo "[setup] oob_management_network_security_setup complete."