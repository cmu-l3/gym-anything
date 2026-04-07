#!/bin/bash
# setup_task.sh — User Access Control Setup
# Prepares the environment, writes the access request document to the desktop,
# and records the initial state.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up User Access Control Setup Task ==="

# 1. Wait for OpManager to be ready
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

# 2. Record task start timestamp and initial user count
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/user_access_task_start.txt
date +%s > /tmp/task_start_timestamp

# Query initial user count from DB
INITIAL_USER_COUNT=$(opmanager_query "SELECT COUNT(*) FROM aaalogin;" 2>/dev/null | tr -d ' ' || echo "0")
if [[ ! "$INITIAL_USER_COUNT" =~ ^[0-9]+$ ]]; then
    INITIAL_USER_COUNT="0"
fi
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt
echo "[setup] Initial user count recorded: $INITIAL_USER_COUNT"

# 3. Write the Access Request Form to the Desktop
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/access_request_form.txt" << 'EOF'
================================================================
         IT ACCESS REQUEST FORM — OpManager Platform
         Request ID: AR-2024-0847
         Approved by: CISO Office, 2024-11-15
================================================================

REQUESTOR: Alex Rivera, IT Operations Manager
SYSTEM: ManageEngine OpManager (http://localhost:8060)
JUSTIFICATION: Team onboarding — individual named accounts required
               per InfoSec Policy ISP-AC-003 (No Shared Credentials)

─────────────────────────────────────────────────────────────────

ACCOUNT 1 — L1 Helpdesk
  Username:    helpdesk-tier1
  Full Name:   Jordan Mitchell
  Email:       j.mitchell@company.internal
  Password:    HdT1@Secure2024
  Role:        Operator
  Purpose:     Acknowledge alerts, view device status, basic triage

ACCOUNT 2 — L2 Network Engineering
  Username:    neteng-sarah
  Full Name:   Sarah Chen
  Email:       s.chen@company.internal
  Password:    NeS@Secure2024
  Role:        Operator
  Purpose:     Deep investigation, device configuration review

ACCOUNT 3 — Compliance Auditor (Quarterly PCI-DSS Review)
  Username:    auditor-compliance
  Full Name:   David Park
  Email:       d.park@company.internal
  Password:    AuC@Secure2024
  Role:        Read Only
  Purpose:     View-only access for audit evidence collection

─────────────────────────────────────────────────────────────────

NOTES:
- All accounts must be created in OpManager User Manager
- Passwords meet complexity requirements (uppercase, lowercase,
  number, special character)
- Auditor account MUST be Read Only / Viewer — no write access permitted
- Operator accounts should NOT have Administrator privileges
================================================================
EOF

chown ga:ga "$DESKTOP_DIR/access_request_form.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Access Request Form written to $DESKTOP_DIR/access_request_form.txt"

# 4. Ensure Firefox is open on OpManager dashboard
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# 5. Take initial screenshot
take_screenshot "/tmp/user_access_setup_screenshot.png" || true

echo "[setup] === User Access Control Setup Task Complete ==="