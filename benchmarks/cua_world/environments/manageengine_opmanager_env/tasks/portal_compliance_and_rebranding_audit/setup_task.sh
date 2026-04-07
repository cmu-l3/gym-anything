#!/bin/bash
# setup_task.sh — Portal Compliance and Rebranding Audit

source /workspace/scripts/task_utils.sh

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
# Write the compliance checklist to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/compliance_rollout_checklist.txt" << 'CHECKLIST_EOF'
SOC2 COMPLIANCE ROLLOUT CHECKLIST
System: ManageEngine OpManager
Environment: Production
Date: 2024-05-15

ACTION REQUIRED:
Before the system can be handed over to the NOC, the following compliance
and branding configurations must be applied in the application settings.

PART A: SYSTEM REBRANDING
Navigate to Settings > Basic Settings > Rebranding (or similar Rebranding menu)
and apply the following exact values to white-label the application:
1. Company Name: SecureNet Financial
2. Application / Window Title: SecureNet NOC
3. Login Page Title: SecureNet Systems Login

PART B: SECURITY HARDENING
Navigate to Settings > Basic Settings > Security Settings (or General Settings)
and enforce the following access control policies:
1. Session Expiry / Idle Timeout: 10 minutes
2. Account Lockout Threshold: 3 invalid attempts
3. Enable Password Policy and set the minimum password length to 12 characters.

Save all changes.

END OF CHECKLIST
CHECKLIST_EOF

chown ga:ga "$DESKTOP_DIR/compliance_rollout_checklist.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Compliance checklist written to $DESKTOP_DIR/compliance_rollout_checklist.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/portal_compliance_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/portal_compliance_setup_screenshot.png" || true

echo "[setup] portal_compliance_and_rebranding_audit setup complete."