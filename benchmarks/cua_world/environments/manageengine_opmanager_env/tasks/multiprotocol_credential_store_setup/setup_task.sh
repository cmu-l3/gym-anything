#!/bin/bash
# setup_task.sh — Multi-Protocol Credential Store Setup

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
# Write credential specification file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/credential_spec.txt" << 'SPEC_EOF'
================================================================
 CLIENT ONBOARDING - NETWORK CREDENTIAL SPECIFICATION
 Prepared by: ACME Corp Security Team
 Document Version: 1.4 | Classification: INTERNAL
 Date: 2024-11-15
================================================================

The following credential profiles must be configured in the
network monitoring platform before initiating discovery of the
ACME Corp production environment. All values are case-sensitive.

────────────────────────────────────────────────────────────────
CREDENTIAL 1: Linux Infrastructure (SSH)
────────────────────────────────────────────────────────────────
  Profile Name:    linux-admin-cred
  Protocol:        SSH
  Username:        monitor
  Password:        Mon1tor@2024
  Port:            22 (default)
  Notes:           Used for all RHEL/Ubuntu servers in racks A1-A8

────────────────────────────────────────────────────────────────
CREDENTIAL 2: Legacy Network Equipment (Telnet)
────────────────────────────────────────────────────────────────
  Profile Name:    legacy-switch-cred
  Protocol:        Telnet
  Username:        netadmin
  Password:        Sw1tchM0n!
  Port:            23 (default)
  Notes:           Cisco 2960/3560 switches pending EOL replacement

────────────────────────────────────────────────────────────────
CREDENTIAL 3: SNMP v3 Secure Monitoring
────────────────────────────────────────────────────────────────
  Profile Name:    secure-snmpv3-cred
  SNMP Version:    v3
  Security Name:   snmpMonitor
  Security Level:  authPriv
  Auth Protocol:   SHA
  Auth Password:   Auth@Secure2024
  Priv Protocol:   AES128
  Priv Password:   Priv@Secure2024
  Notes:           All v3-capable infrastructure (firewalls, core routers)

────────────────────────────────────────────────────────────────
CREDENTIAL 4: Windows Server Domain (WMI)
────────────────────────────────────────────────────────────────
  Profile Name:    windows-domain-cred
  Protocol:        WMI / Windows
  Domain:          CORPNET
  Username:        svc_monitor
  Password:        W1nM0n@2024
  Notes:           Active Directory service account for all domain servers

================================================================
 END OF SPECIFICATION — Do not share outside IT Operations
================================================================
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/credential_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Credential specification written to $DESKTOP_DIR/credential_spec.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/credential_setup_screenshot.png" || true

echo "[setup] setup_task.sh complete."