#!/bin/bash
# setup_task.sh — Dynamic Asset Tagging and Compliance Grouping
# Waits for OpManager, writes the policy document, and records initial state.

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

# ------------------------------------------------------------
# Write Asset Tagging Policy to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/asset_tagging_policy.txt" << 'POLICY_EOF'
ASSET TAGGING & COMPLIANCE POLICY
Effective Date: 2024-04-01
Owner: Information Security

All managed infrastructure in OpManager must be tagged with compliance data to ensure proper monitoring visibility and auditing.

ACTION ITEMS:

1. Create Custom Fields:
   Navigate to Settings > Configuration > Custom Fields (or Basic Settings > Custom Fields).
   Create the following two Text fields:
   - Field Name 1: Compliance_Framework
   - Field Name 2: Data_Classification

2. Tag In-Scope Assets:
   Navigate to the Inventory, locate the primary gateway/localhost device (IP 127.0.0.1), and edit its Custom Fields/Properties to apply the following values:
   - Compliance_Framework: PCI-DSS
   - Data_Classification: Confidential

3. Create Dynamic Compliance Group:
   Navigate to Groups (Settings > Configuration > Groups OR Inventory > Groups).
   Create a new Rule-based (Dynamic) Group with the following details:
   - Group Name: PCI-In-Scope-Assets
   - Grouping Criteria: Set the rule so that the Custom Field 'Compliance_Framework' contains or equals 'PCI-DSS'.

Save all configurations. Security will verify the group membership and tags.
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/asset_tagging_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Asset tagging policy written to $DESKTOP_DIR/asset_tagging_policy.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/asset_tagging_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/asset_tagging_setup_screenshot.png" || true

echo "[setup] dynamic_asset_tagging_compliance_grouping setup complete."