#!/bin/bash
# setup_task.sh — Discovery Exclusion Filter Configuration
# Prepares the environment by writing the exclusion policy to the desktop
# and waiting for OpManager to be ready.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Discovery Exclusion Filter Configuration Task ==="

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
# 2. Write exclusion policy file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/discovery_exclusion_policy.txt" << 'POLICY_EOF'
DISCOVERY EXCLUSION POLICY
Document ID: NET-POL-EXC-09
Version: 1.1

BACKGROUND:
Our automated network discovery is erroneously inventorying transient devices 
such as guest laptops, IP phones, and backend storage networks. This consumes 
licenses and poll cycles.

ACTION REQUIRED:
Please configure the following exclusions in ManageEngine OpManager.
Navigate to: Settings > Discovery > Ignore MAC/IP (or Discovery Filters).

=========================================
SECTION 1: IP ADDRESS EXCLUSIONS
=========================================
Add the following two ranges to the Ignore IP Address configuration:

Range 1 (Storage Backend Network):
  Start IP: 10.50.1.1
  End IP:   10.50.1.255

Range 2 (Guest WiFi DHCP Scope):
  Start IP: 172.16.200.1
  End IP:   172.16.200.254

=========================================
SECTION 2: MAC ADDRESS EXCLUSIONS
=========================================
Add the following two Organizationally Unique Identifiers (OUIs) to the 
Ignore MAC Address configuration:

MAC OUI 1 (VMware Virtual NICs):
  MAC Address: 00:50:56
  Description: VMware VM transient interfaces

MAC OUI 2 (Polycom IP Phones):
  MAC Address: 00:04:F2
  Description: Polycom VoIP endpoints

Ensure all entries are saved.
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/discovery_exclusion_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Exclusion policy written to $DESKTOP_DIR/discovery_exclusion_policy.txt"

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/discovery_exclusion_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/discovery_exclusion_setup_screenshot.png" || true

echo "[setup] === Setup Complete ==="