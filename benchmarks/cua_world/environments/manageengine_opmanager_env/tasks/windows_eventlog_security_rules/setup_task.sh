#!/bin/bash
# setup_task.sh — Windows Event Log Security Rules
# Waits for OpManager to be ready, writes the policy document to the desktop,
# and prepares the environment for the agent.

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
# Write security policy document to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/eventlog_audit_policy.txt" << 'POLICY_EOF'
Information Security Audit Policy: Windows Event Logs
Document ID: SEC-POL-WIN-001
Effective Date: 2024-04-01

All Domain Controllers and critical Windows servers must have explicit monitoring rules for the following security events. Please configure these in the Network Management System (OpManager).

REQUIREMENTS:
Navigate to Settings > Monitoring > Event Log Rules in OpManager and create the following three rules.

Rule 1: Failed Logon Attempts
- Rule Name: Sec-Failed-Logon
- Log Name: Security
- Event Type: Failure Audit
- Event ID: 4625
- Severity: Critical

Rule 2: Account Lockouts
- Rule Name: Sec-Account-Lockout
- Log Name: Security
- Event Type: Success Audit
- Event ID: 4740
- Severity: Trouble

Rule 3: Security Log Cleared
- Rule Name: Sec-Audit-Log-Cleared
- Log Name: Security
- Event Type: Success Audit
- Event ID: 1102
- Severity: Critical

Note: Ensure the exact Event IDs and names are configured.
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/eventlog_audit_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Security policy written to $DESKTOP_DIR/eventlog_audit_policy.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/eventlog_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/eventlog_setup_screenshot.png" || true

echo "[setup] windows_eventlog_security_rules setup complete."