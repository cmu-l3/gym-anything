#!/bin/bash
# setup_task.sh — Discovery Rule Engine Automation
# Waits for OpManager, writes the specification file, and records initial state.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Discovery Rule Engine Automation Task ==="

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
# 2. Write the deployment specification file to Desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/discovery_automation_spec.txt" << 'SPEC_EOF'
DISCOVERY RULE ENGINE CONFIGURATION SPECIFICATION
=================================================
Document Version: 1.1
Target System: ManageEngine OpManager

We are onboarding a new regional branch and need to automate device classification during discovery. Before scanning the subnet, please configure the Discovery Rule Engine so that our edge firewalls and access switches are automatically categorized and placed into the correct monitoring groups.

PREREQUISITE: Create Custom Device Groups
You must first create the following two Custom Device Groups (Inventory -> Groups or Settings -> Groups):
1. Group Name: Edge-Firewalls
2. Group Name: Access-Switches

ACTION ITEM: Create Discovery Rules
Navigate to Settings -> Discovery -> Rule Engine and create the following two rules:

Rule 1: Edge Firewall Automation
---------------------------------
Rule Name: Auto-Edge-Firewall
Criteria: 
  - Device Name (or DNS Name) contains "edge-fw"
Actions:
  - Modify Device Type to: Firewall
  - Add to Group: Edge-Firewalls

Rule 2: Access Switch Automation
---------------------------------
Rule Name: Auto-Access-Switch
Criteria: 
  - Device Name (or DNS Name) contains "acc-sw"
Actions:
  - Modify Device Type to: Switch
  - Add to Group: Access-Switches

Please ensure both rules are saved and active.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/discovery_automation_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification written to $DESKTOP_DIR/discovery_automation_spec.txt"

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/discovery_setup_screenshot.png" || true

echo "[setup] === Setup Complete ==="