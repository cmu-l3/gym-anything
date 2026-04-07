#!/bin/bash
# setup_task.sh — Syslog Security Event Processing Rules
# Creates the security policy document and prepares the environment.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Syslog Security Event Rules Task ==="

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
# 2. Write the Syslog Event Handling Policy to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/syslog_event_policy.txt" << 'POLICY_EOF'
===============================================================
  SYSLOG EVENT HANDLING POLICY v3.1
  Information Security Division
  Effective Date: 2024-12-01
  Classification: Internal Use Only
===============================================================

OVERVIEW
--------
This policy mandates the configuration of syslog processing rules
in the enterprise network monitoring platform (ManageEngine OpManager)
to ensure real-time detection and classification of security-relevant
events from all network infrastructure devices.

All rules MUST be created with EXACT names as specified below.
Rules must generate alarms at the designated severity level.

---------------------------------------------------------------
RULE 1: Authentication Failure Detection
---------------------------------------------------------------
  Rule Name:      SEC-AUTH-FAILURE
  Match String:   authentication failure
  Severity:       Critical
  Description:    Detects failed authentication attempts from
                  network devices indicating potential brute-force
                  or unauthorized access attempts.

---------------------------------------------------------------
RULE 2: Firewall Deny Events
---------------------------------------------------------------
  Rule Name:      SEC-FW-DENY
  Match String:   denied
  Severity:       Warning
  Description:    Captures firewall deny/drop events indicating
                  blocked traffic that may represent reconnaissance
                  or attack activity.

---------------------------------------------------------------
RULE 3: Configuration Change Audit
---------------------------------------------------------------
  Rule Name:      SEC-CONFIG-CHANGE
  Match String:   configuration changed
  Severity:       Informational
  Description:    Tracks device configuration changes for change
                  management audit trail compliance (SOX/PCI-DSS).

---------------------------------------------------------------
RULE 4: Privilege Escalation Alert
---------------------------------------------------------------
  Rule Name:      SEC-PRIV-ESCALATION
  Match String:   privilege level changed
  Severity:       Critical
  Description:    Detects privilege level changes on network
                  devices that could indicate insider threat or
                  compromised credentials.

---------------------------------------------------------------
RULE 5: Interface Link State Flapping
---------------------------------------------------------------
  Rule Name:      SEC-LINK-FLAP
  Match String:   link state changed
  Severity:       Warning
  Description:    Monitors link state transitions that may indicate
                  physical layer attacks, cable tampering, or
                  infrastructure instability.

===============================================================
  END OF POLICY - Implement all 5 rules before next SOC shift
===============================================================
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/syslog_event_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Syslog security policy written to $DESKTOP_DIR/syslog_event_policy.txt"

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/syslog_rules_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/syslog_rules_setup_screenshot.png" || true

echo "[setup] === Syslog Security Event Rules Task Setup Complete ==="