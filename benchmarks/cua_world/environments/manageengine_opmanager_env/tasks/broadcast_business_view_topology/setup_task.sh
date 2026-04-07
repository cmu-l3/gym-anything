#!/bin/bash
# setup_task.sh — Broadcast Business View Topology Task Setup
# Waits for OpManager, writes the topology spec to the desktop, and prepares Firefox.

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
# Write the specification file to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/broadcast_infrastructure_layout.txt" << 'SPEC_EOF'
=========================================================
BROADCAST INFRASTRUCTURE LAYOUT SPECIFICATION
Version: 1.4 | Date: 2024-11-15
Prepared by: Engineering Manager, Regional TV Station
=========================================================

SECTION 1: BUSINESS VIEW REQUIREMENTS
--------------------------------------
The following logical topology views must be created in
the network monitoring system (OpManager) to represent
the three primary segments of our IP broadcast facility.

VIEW 1: Broadcast-Production-Network
  Purpose: Visualize the studio production IP network
  including camera feeds, audio consoles, graphics
  engines, and production switchers operating on
  SMPTE 2110 transport. This view covers all production
  studio floor equipment and associated network switches.

VIEW 2: Master-Control-Room
  Purpose: Represent the MCR (Master Control Room)
  infrastructure including playout servers, automation
  systems, branding/graphics insertion, and signal
  routing. The MCR is the final quality control point
  before distribution.

VIEW 3: Distribution-Backbone
  Purpose: Map the distribution network carrying
  program output to satellite uplinks, fiber
  distribution, streaming encoders, and CDN origin
  servers. This is the outbound signal path.

SECTION 2: DEVICE GROUP REQUIREMENTS
--------------------------------------
All broadcast-related devices should be organized under
a single top-level device group for filtering:

GROUP: Broadcast-Systems
  Description: All devices classified as broadcast
  infrastructure including production, MCR, and
  distribution equipment.

SECTION 3: IMPLEMENTATION NOTES
--------------------------------------
- All views must be created with exact names as specified
  above (case-sensitive, hyphens preserved).
- Each view should include a description that reflects
  its stated purpose.
- The device group must be created before devices can be
  assigned in future phases.
- This document supersedes any prior topology naming.

END OF SPECIFICATION
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/broadcast_infrastructure_layout.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification file written to $DESKTOP_DIR/broadcast_infrastructure_layout.txt"

# ------------------------------------------------------------
# Record task start timestamp (anti-gaming)
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/topology_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/topology_setup_screenshot.png" || true

echo "[setup] broadcast_business_view_topology setup complete."