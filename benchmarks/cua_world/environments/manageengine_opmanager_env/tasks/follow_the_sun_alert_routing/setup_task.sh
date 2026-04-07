#!/bin/bash
# setup_task.sh — Follow-the-Sun Alert Routing
# Waits for OpManager, writes the policy, and opens Firefox.

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
# Write the Global Shift Policy file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/global_shift_policy.txt" << 'POLICY_EOF'
GLOBAL SHIFT NOTIFICATION POLICY
Document ID: OPS-POL-009
Version: 1.1

OVERVIEW:
To prevent alert fatigue and ensure alerts are routed to the on-duty regional Network Operations Center (NOC), three distinct email notification profiles must be created in OpManager. Ensure these are strictly time-bound (NOT 24x7).

REQUIREMENTS:

1. APAC Regional Shift
   - Profile Name: APAC-Regional-Alerts
   - Target Email: apac-noc@global.internal
   - Active Days: Monday through Friday
   - Active Time: 00:00 to 08:00
   - Criteria: Critical Device Alarms

2. EMEA Regional Shift
   - Profile Name: EMEA-Regional-Alerts
   - Target Email: emea-noc@global.internal
   - Active Days: Monday through Friday
   - Active Time: 08:00 to 16:00
   - Criteria: Critical Device Alarms

3. AMER Regional Shift
   - Profile Name: AMER-Regional-Alerts
   - Target Email: amer-noc@global.internal
   - Active Days: Monday through Friday
   - Active Time: 16:00 to 23:59 (or 24:00)
   - Criteria: Critical Device Alarms

INSTRUCTIONS:
Navigate to Settings > Notifications > Notification Profiles. Create a new Email profile for each region above. Ensure the "Time Window" is explicitly configured to match the active days and hours.

POLICY_EOF

chown ga:ga "$DESKTOP_DIR/global_shift_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Shift policy written to $DESKTOP_DIR/global_shift_policy.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/follow_the_sun_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/follow_the_sun_setup_screenshot.png" || true

echo "[setup] follow_the_sun_alert_routing setup complete."