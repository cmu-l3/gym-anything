#!/bin/bash
# setup_task.sh — SNMP Credential Security Audit
# Writes the SNMP security hardening policy document to the desktop.


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
# Write SNMP security policy file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/snmp_security_policy.txt" << 'POLICY_EOF'
SNMP Security Hardening Policy
Document ID: SEC-POL-0042
Version: 1.2
Effective Date: 2024-01-01
Owner: Information Security Team
Approved By: CISO

POLICY REQUIREMENTS
---------------------

REQUIREMENT 1 — CREDENTIAL RENAME
All SNMP credential profiles in OpManager that use the community string 'public'
must be updated. The credential name 'public' must be replaced with the new
secure credential profile named 'netops-monitor-2024' using community string
'netops-monitor-2024'.

To update: Navigate to Settings > Discovery > SNMP Credentials in OpManager.
Delete or rename the existing 'public' credential profile and create a new
credential profile named 'netops-monitor-2024' with community string
'netops-monitor-2024' and SNMP version v2c.

REQUIREMENT 2 — NEW DEVICE ADDITION
Add the following new device to OpManager monitoring:
  Device IP: 192.168.1.100
  Display Name: Perimeter-Firewall-01
  Device Type: Firewall
  SNMP Community String: netops-dmz-2024
  SNMP Version: v2c

The device should be added via Settings > Discovery > New Device or
via the Add Device option in the Inventory section.

REQUIREMENT 3 — SNMP CREDENTIAL PROFILE CREATION
Ensure the following SNMP credential profiles exist in OpManager
(Settings > Discovery > SNMP Credentials):
  Profile 1: netops-monitor-2024 (community: netops-monitor-2024, v2c)
  Profile 2: netops-dmz-2024 (community: netops-dmz-2024, v2c)

AUDIT EVIDENCE
All changes must be saved in OpManager. The security team will audit via
the credential store and device inventory.

END OF POLICY
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/snmp_security_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] SNMP security policy written to $DESKTOP_DIR/snmp_security_policy.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/snmp_security_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/snmp_security_setup_screenshot.png" || true

echo "[setup] snmp_credential_security_audit setup complete."
