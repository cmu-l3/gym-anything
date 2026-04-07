#!/bin/bash
# setup_task.sh — SNMP Trap Processor Config

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s. Continuing." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Write Trap Processing Specification file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/trap_processing_spec.txt" << 'SPEC_EOF'
SNMP Trap Processing Specification
Document ID: NET-TRAP-001
Date: 2024-05-15
Role: Broadcast Infrastructure / Telecom

BACKGROUND
----------
New IP-based transport equipment (AoIP, SMPTE 2110) has been deployed across the facility.
We must capture and properly categorize standards-based SNMPv2 traps from this equipment.

REQUIREMENTS
------------
Create four (4) SNMP Trap Processors in OpManager with the exact settings below:

1. Link Down Trap
   - Name: LinkDown-Critical-Trap
   - Trap OID: 1.3.6.1.6.3.1.1.5.3
   - Severity: Critical (or Service Down)

2. Link Up Trap
   - Name: LinkUp-Recovery-Trap
   - Trap OID: 1.3.6.1.6.3.1.1.5.4
   - Severity: Clear (or Service Up)

3. Authentication Failure Trap
   - Name: AuthFailure-Security-Trap
   - Trap OID: 1.3.6.1.6.3.1.1.5.5
   - Severity: Major

4. Cold Start Trap
   - Name: ColdStart-Device-Trap
   - Trap OID: 1.3.6.1.6.3.1.1.5.1
   - Severity: Warning

INSTRUCTIONS
------------
Log in to OpManager (http://localhost:8060) as admin/Admin@123.
Navigate to the SNMP Trap Processors section (typically under Settings > Monitoring > SNMP Trap Processors, or Settings > Basic Settings > SNMP Trap Processors).
Create each processor. If prompted for a device or category, select all devices or leave broad scope.
Save each processor to persist it in the database.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/trap_processing_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Spec file written to $DESKTOP_DIR/trap_processing_spec.txt"

# ------------------------------------------------------------
# Record task start timestamp and initial DB state
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/trap_config_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/trap_processor_setup_screenshot.png" || true

echo "[setup] snmp_trap_processor_config setup complete."