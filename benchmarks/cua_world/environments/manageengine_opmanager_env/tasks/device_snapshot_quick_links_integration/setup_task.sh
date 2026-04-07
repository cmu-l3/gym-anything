#!/bin/bash
# setup_task.sh — Device Snapshot Quick Links Integration
# Waits for OpManager, records start state, writes the specification file, and opens Firefox.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Quick Links Integration Task ==="

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
# 2. Write the specification file to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/noc_quick_links_spec.txt" << 'SPEC_EOF'
NOC Quick Links Integration Specification

Please configure the following Quick Links in OpManager so that our engineers can quickly pivot from a device snapshot page to external IT management tools.

Navigate to Settings -> Configuration -> Quick Links (or equivalent configuration area) and add the following four shortcuts:

1. Splunk
   Name: Splunk-Host-Search
   URL: https://splunk.secops.internal/search?q=host%3D${deviceName}

2. IPAM
   Name: IPAM-Subnet-Lookup
   URL: https://netbox.infra.internal/ipam/ip-addresses/?q=${deviceIpAddress}

3. Ansible AWX
   Name: Ansible-Playbook-Runner
   URL: https://awx.infra.internal/templates/launch/?limit=${deviceIpAddress}

4. Warranty Tracker
   Name: Hardware-Warranty-Check
   URL: https://warranty-tracker.internal/check?host=${deviceName}

Note: You can select the dynamic variables (like deviceName and deviceIpAddress) from the UI dropdown in OpManager or type them directly into the URL template.

END OF SPECIFICATION
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/noc_quick_links_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification file written to $DESKTOP_DIR/noc_quick_links_spec.txt"

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/quick_links_setup_screenshot.png" || true

echo "[setup] === Setup Complete ==="