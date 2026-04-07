#!/bin/bash
# setup_task.sh — FIPS Compliant SNMPv3 Credential Migration

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

# Record task start timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/snmpv3_migration_task_start.txt
date +%s > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# Create the SNMPv3 policy document
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/snmpv3_migration_policy.txt" << 'EOF'
=================================================================
ENTERPRISE INFOSEC POLICY: SNMPv3 CREDENTIAL MIGRATION
STATUS: MANDATORY / FIPS-COMPLIANT
=================================================================

All network monitoring must utilize SNMPv3 with SHA authentication 
and AES privacy. MD5 and DES are strictly prohibited.

Please configure the following three SNMPv3 profiles in the NMS:

1. Profile Name: Core-Network-v3
   - Version: v3
   - User Name: core-sec-admin
   - Context Name: core-ctx
   - Authentication Protocol: SHA (or SHA-256)
   - Authentication Password: CoreAuthSecure123!
   - Privacy Protocol: AES (or AES-128/256)
   - Privacy Password: CorePrivSecure123!

2. Profile Name: Edge-Firewall-v3
   - Version: v3
   - User Name: edge-sec-admin
   - Context Name: edge-ctx
   - Authentication Protocol: SHA (or SHA-256)
   - Authentication Password: EdgeAuthSecure123!
   - Privacy Protocol: AES
   - Privacy Password: EdgePrivSecure123!

3. Profile Name: DMZ-Services-v3
   - Version: v3
   - User Name: dmz-sec-admin
   - Context Name: dmz-ctx
   - Authentication Protocol: SHA (or SHA-256)
   - Authentication Password: DmzAuthSecure123!
   - Privacy Protocol: AES
   - Privacy Password: DmzPrivSecure123!
EOF

chown ga:ga "$DESKTOP_DIR/snmpv3_migration_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] SNMPv3 policy written to $DESKTOP_DIR/snmpv3_migration_policy.txt"

# Ensure Firefox is open on OpManager dashboard
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/snmpv3_migration_setup_screenshot.png" || true

echo "[setup] fips_compliant_snmpv3_credential_migration setup complete."