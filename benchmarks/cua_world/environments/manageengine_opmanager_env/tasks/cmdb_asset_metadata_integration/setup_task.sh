#!/bin/bash
# setup_task.sh — CMDB Asset Metadata Integration

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
# Write CMDB Asset Classification Policy file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/asset_classification_policy.txt" << 'POLICY_EOF'
ITSM & CMDB Asset Classification Policy
Document ID: ITSM-POL-0018
Effective Date: 2024-03-01

BACKGROUND
All managed infrastructure must be tagged with appropriate metadata to support the upcoming PCI-DSS compliance audit and sync with our central CMDB.

REQUIREMENT 1 — DEVICE TEMPLATE CREATION
Create a new custom device template in OpManager for the central monitoring servers.
- Template Name: Management-Appliance
- Vendor: ManageEngine
- Category: Server

REQUIREMENT 2 — CUSTOM FIELD DEFINITIONS
Create the following three new Custom Fields in OpManager (Text type):
1. CostCenter
2. AssetOwner
3. ComplianceScope

REQUIREMENT 3 — DEVICE TAGGING
Locate the primary management server (localhost / 127.0.0.1) in the device inventory and apply the following updates:
- Change its Device Template to: Management-Appliance
- Set CostCenter to: CC-90210
- Set AssetOwner to: sec-ops-team
- Set ComplianceScope to: PCI-DSS

Save all changes. The auditor will verify these fields via the database.
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/asset_classification_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Asset Classification Policy written to $DESKTOP_DIR/asset_classification_policy.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/cmdb_integration_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/cmdb_integration_setup_screenshot.png" || true

echo "[setup] cmdb_asset_metadata_integration setup complete."