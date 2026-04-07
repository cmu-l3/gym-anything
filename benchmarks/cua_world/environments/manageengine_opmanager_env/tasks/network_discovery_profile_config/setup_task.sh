#!/bin/bash
# setup_task.sh — Automated Network Discovery Profile Configuration
# Waits for OpManager, writes the site survey spec document, and opens Firefox.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Write Site Survey Plan file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/site_survey_discovery_plan.txt" << 'EOF'
==========================================================================
SITE SURVEY & NETWORK DISCOVERY PLAN
Building A - New Office Deployment
Document Version: 1.4 | Date: 2024-11-15
Prepared by: Network Installation Team
==========================================================================

OVERVIEW
--------
Building A has been fully cabled and provisioned across three floors.
All managed network devices have been assigned IP addresses from the
10.1.x.0/24 address space. Each floor uses a unique SNMP community
string per the security policy. OpManager must be configured with
discovery profiles for each floor to enable automated device inventory.

DISCOVERY PROFILES REQUIRED
----------------------------

PROFILE 1: Floor-1-Core-Network
  Subnet:        10.1.1.0/24
  IP Range:      10.1.1.1 - 10.1.1.254
  SNMP Version:  v2c
  Community:     floor1-monitor
  Equipment:     2x Core switches, 8x Access points, 1x UPS
  Notes:         Building A, Floor 1 — Core switching and Wi-Fi infrastructure

PROFILE 2: Floor-2-Office-Network
  Subnet:        10.1.2.0/24
  IP Range:      10.1.2.1 - 10.1.2.254
  SNMP Version:  v2c
  Community:     floor2-monitor
  Equipment:     4x PoE switches, 12x IP phones, 6x Access points
  Notes:         Building A, Floor 2 — Office workstation and VoIP network

PROFILE 3: Floor-3-Lab-Network
  Subnet:        10.1.3.0/24
  IP Range:      10.1.3.1 - 10.1.3.254
  SNMP Version:  v2c
  Community:     floor3-monitor
  Equipment:     2x Managed switches, 4x Test servers, 3x Protocol analyzers
  Notes:         Building A, Floor 3 — R&D lab and test equipment network

IMPLEMENTATION NOTES
--------------------
- Discovery profile names MUST match exactly as specified above.
- SNMP credentials should be created as v2c profiles if not already present.
- Discovery does not need to be executed immediately; configuration only.
- All three profiles must be saved before shift handover at 18:00.

==========================================================================
END OF DOCUMENT
==========================================================================
EOF

chown ga:ga "$DESKTOP_DIR/site_survey_discovery_plan.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Site survey spec written to $DESKTOP_DIR/site_survey_discovery_plan.txt"

# ------------------------------------------------------------
# Record task start timestamp and initial state
# ------------------------------------------------------------
date +%s > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager 3 || true

# Take an initial screenshot
take_screenshot "/tmp/discovery_setup_screenshot.png" || true

echo "[setup] Automated Network Discovery Profile Configuration setup complete."