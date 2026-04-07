#!/bin/bash
# setup_task.sh — SNMPv3 AuthPriv Security Credential Setup

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
# Write SNMPv3 security mandate to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/snmpv3_mandate.txt" << 'POLICY_EOF'
SNMPv3 AUTHPRIV DEPLOYMENT MANDATE
----------------------------------
All legacy SNMP monitoring must be replaced with SNMPv3 utilizing 
AuthPriv (Authentication and Privacy) for encryption and integrity.

Please create the following two SNMPv3 credentials in OpManager:

--- Profile 1 ---
Protocol: SNMPv3
Credential Name: Fed-Core-SNMPv3
Username: core_v3_admin
Context Name: core_routers
Authentication Protocol: SHA-256 (or SHA if SHA-256 is unavailable)
Authentication Password: CoreAuth!2026
Privacy Protocol: AES-128 (or AES if AES-128 is unavailable)
Privacy Password: CorePriv!2026

--- Profile 2 ---
Protocol: SNMPv3
Credential Name: Fed-DMZ-SNMPv3
Username: dmz_v3_admin
Context Name: dmz_fw
Authentication Protocol: SHA-256 (or SHA if SHA-256 is unavailable)
Authentication Password: DmzAuth!2026
Privacy Protocol: AES-128 (or AES if AES-128 is unavailable)
Privacy Password: DmzPriv!2026

POLICY_EOF

chown ga:ga "$DESKTOP_DIR/snmpv3_mandate.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start.txt
date +%s > /tmp/task_start_timestamp

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true
sleep 3
take_screenshot "/tmp/task_initial.png" || true

echo "[setup] snmpv3_authpriv_security_credential_setup setup complete."