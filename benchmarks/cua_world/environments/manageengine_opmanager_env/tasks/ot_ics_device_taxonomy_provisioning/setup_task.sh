#!/bin/bash
# setup_task.sh — OT ICS Device Taxonomy Provisioning
# Prepares the OpManager environment and creates the specification document.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up OT ICS Device Taxonomy Task ==="

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
# ------------------------------------------------------------
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
# 2. Record task start timestamp (Anti-Gaming)
# ------------------------------------------------------------
date +%s > /tmp/task_start_time.txt
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/ot_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 3. Create the Specification Document
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/ot_device_specs.txt" << 'EOF'
ICS DEVICE TAXONOMY SPECIFICATION
Version: 1.1
Prepared By: OT Integration Architect
Date: 2024-04-10

ACTION REQUIRED:
The standard OpManager IT taxonomy lacks appropriate classifications for our factory floor hardware. Before the upcoming subnet discovery, you must provision the following custom categories, vendors, and templates into OpManager (Settings > Configuration).

PART 1: NEW DEVICE CATEGORIES
-----------------------------
Create the following Device Categories:
1. Category Name: Industrial-PLC
2. Category Name: HVAC-Sensor

PART 2: NEW VENDORS
-----------------------------
Create the following Vendors:
1. Vendor Name: Siemens
2. Vendor Name: Schneider-Electric

PART 3: NEW DEVICE TEMPLATES
-----------------------------
Create the following Device Templates mapped to the above categories/vendors:

Template A:
- Template Name: Siemens-S7-1500
- Vendor: Siemens
- Category: Industrial-PLC
- System OID: .1.3.6.1.4.1.4329.1.1

Template B:
- Template Name: Schneider-HVAC-Monitor
- Vendor: Schneider-Electric
- Category: HVAC-Sensor
- System OID: .1.3.6.1.4.1.3833.1.2

Please save all changes. Verification will scan the device templates and category databases.
EOF

chown -R ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification document created at $DESKTOP_DIR/ot_device_specs.txt"

# ------------------------------------------------------------
# 4. Ensure Firefox is open and take screenshot
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# Maximize Firefox for better agent visibility
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot to prove starting state
take_screenshot "/tmp/ot_ics_setup_screenshot.png" || true

echo "[setup] === Task Setup Complete ==="