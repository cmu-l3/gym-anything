#!/bin/bash
# setup_task.sh — Data Center Power Infrastructure Monitoring Setup

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
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

# Create spec file
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/ups_monitoring_spec.txt" << 'SPEC_EOF'
DATA CENTER FACILITIES - MONITORING SPECIFICATION
=================================================
System: ManageEngine OpManager
Target: APC Symmetra UPS Row

REQUIREMENT 1: MANAGEMENT CREDENTIALS
Create a new SNMPv3 credential profile.
- Name: Facility-UPS-V3
- Security Level: AuthPriv
- Authentication Protocol: SHA
- Authentication Password: AuthPassword2024
- Privacy Protocol: AES-128
- Privacy Password: PrivPassword2024

REQUIREMENT 2: DEVICE TEMPLATE
Create a custom device template for the premium UPS units.
- Template Name: Datacenter-UPS-Premium
- Vendor: APC
- Category: UPS
- System OID: .1.3.6.1.4.1.318.1.3.27

REQUIREMENT 3: CUSTOM OID MONITOR
Within the "Datacenter-UPS-Premium" template, add a custom SNMP monitor to track battery capacity.
- Monitor Name: Battery-Remaining-Capacity
- OID: .1.3.6.1.4.1.318.1.1.1.2.2.1.0
- Polling Interval: 2 minutes

REQUIREMENT 4: NOTIFICATION PROFILE
Create an email notification profile to alert the facilities team.
- Profile Name: Facilities-Power-Alert
- Delivery Email: power-ops@datacenter.internal
- Criteria: Any alarm triggered on devices in the "UPS" category.

END OF SPECIFICATION
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/ups_monitoring_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true

# Record task start timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/power_infra_task_start.txt
date +%s > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# Ensure Firefox is open on OpManager dashboard
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/task_initial_screenshot.png" || true

echo "[setup] facility_power_infrastructure_tuning setup complete."