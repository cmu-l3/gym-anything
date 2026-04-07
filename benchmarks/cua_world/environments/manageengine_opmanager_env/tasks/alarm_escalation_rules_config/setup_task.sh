#!/bin/bash
# setup_task.sh — Alarm Escalation Rules Configuration
# Prepares the environment, creates the policy document, and records baseline state.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Alarm Escalation Rules Task ==="

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
# 2. Write the Incident Response Escalation Policy to Desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/alarm_escalation_policy.txt" << 'POLICY_EOF'
INCIDENT RESPONSE ESCALATION POLICY
Document ID: IR-POL-2026-03
Effective Date: March 15, 2026
Target System: ManageEngine OpManager

OVERVIEW:
All unacknowledged alarms must be escalated to the appropriate response teams
based on severity and dwell time. Configure the following four Alarm Escalation Rules
in OpManager (typically found under Settings -> Notifications / Alarms).

RULE 1: Critical Alarms
- Rule Name: Critical-Immediate-Escalation
- Criteria: Alarm Severity is Critical
- Escalation Time: If alarm is unacknowledged for 5 minutes
- Action/Recipient: Email to soc-critical@msp-ops.internal

RULE 2: Major/Trouble Alarms
- Rule Name: Major-Triage-Escalation
- Criteria: Alarm Severity is Trouble (or Major)
- Escalation Time: If alarm is unacknowledged for 15 minutes
- Action/Recipient: Email to noc-triage@msp-ops.internal

RULE 3: Device Down Events
- Rule Name: DeviceDown-Emergency-Escalation
- Criteria: Device Down alarms
- Escalation Time: If alarm is unacknowledged for 3 minutes
- Action/Recipient: Email to emergency-response@msp-ops.internal

RULE 4: Warning Alarms
- Rule Name: Warning-Review-Escalation
- Criteria: Alarm Severity is Warning
- Escalation Time: If alarm is unacknowledged for 30 minutes
- Action/Recipient: Email to ops-review@msp-ops.internal

IMPLEMENTATION NOTES:
- Names and email addresses must be entered exactly as shown.
- Ensure all rules are saved and active.
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/alarm_escalation_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Policy document written to $DESKTOP_DIR/alarm_escalation_policy.txt"

# ------------------------------------------------------------
# 3. Record task start timestamp for anti-gaming
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time.txt
date +%s > /tmp/task_start_timestamp.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/task_initial.png" || true

echo "[setup] === Alarm Escalation Rules Task Setup Complete ==="