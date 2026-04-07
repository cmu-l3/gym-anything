#!/bin/bash
# setup_task.sh — SLA Business Hours and Holidays Config
# Waits for OpManager, writes the policy document, and opens Firefox.

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
# Write the SLA policy document to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/sla_calendar_policy_2026.txt" << 'POLICY_EOF'
SLA Operations Calendar Policy
Effective Year: 2026

1. BUSINESS HOUR PROFILES
Configure the following two business hour profiles in OpManager (typically found under Settings > Basic Settings > Business Hours, or Settings > General Settings > Business Hours).

Profile Name: US-Trading-Hours
Days: Monday to Friday
Time Window: 08:00 to 17:00

Profile Name: APAC-Extended-Support
Days: Monday to Saturday
Time Window: 07:00 to 19:00

2. CORPORATE HOLIDAY LIST
Configure the following global holiday list.

List Name: Global-Corporate-Holidays-2026
Dates to Add:
- January 1, 2026 (New Year's Day)
- May 1, 2026 (International Workers' Day)

END OF POLICY
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/sla_calendar_policy_2026.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] SLA Calendar policy written to $DESKTOP_DIR/sla_calendar_policy_2026.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/sla_calendar_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/sla_calendar_setup_screenshot.png" || true

echo "[setup] sla_business_hours_and_holidays_config setup complete."