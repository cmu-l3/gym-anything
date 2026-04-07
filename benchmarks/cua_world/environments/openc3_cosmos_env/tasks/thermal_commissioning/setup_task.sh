#!/bin/bash
echo "=== Setting up Thermal Commissioning task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_NAME="thermal_commissioning"

# ── 1. Remove stale output files BEFORE recording timestamp ──────
rm -f /home/ga/Desktop/commissioning_report.json 2>/dev/null || true
rm -f /home/ga/Desktop/commissioning_briefing.txt 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_ground_truth.json 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_orig_limits_*.json 2>/dev/null || true

# ── 2. Record start timestamp (AFTER cleanup) ────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start recorded: $(cat /tmp/${TASK_NAME}_start_ts)"

# ── 3. Wait for COSMOS API ────────────────────────────────────────
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 120; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# ── 4. Record baseline state for all 4 sensors ───────────────────
echo "Recording baseline limits for all temperature sensors..."
for ITEM in TEMP1 TEMP2 TEMP3 TEMP4; do
    LIMITS=$(cosmos_api "get_limits" "\"INST\",\"HEALTH_STATUS\",\"$ITEM\"" 2>/dev/null | jq -c '.result // []' 2>/dev/null || echo "[]")
    echo "$LIMITS" > /tmp/${TASK_NAME}_orig_limits_${ITEM}.json
    echo "  $ITEM original limits: $LIMITS"
done

# Record initial INST2_INT state (use get_interface; interface_state is restricted in OpenC3 6.x)
INST2_STATE=$(cosmos_api "get_interface" '"INST2_INT"' 2>/dev/null \
    | jq -r '.result.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
echo "Initial INST2_INT state: $INST2_STATE"

# Record initial TEMP3 live value (before override)
TEMP3_BASELINE=$(cosmos_tlm "INST HEALTH_STATUS TEMP3" 2>/dev/null || echo "0")
echo "TEMP3 baseline value: $TEMP3_BASELINE"

# ── 5. Inject Fault 1: Disconnect INST2_INT ───────────────────────
# Simulates previous shift leaving the interface down
echo "Injecting fault: disconnecting INST2_INT..."
cosmos_api "disconnect_interface" '"INST2_INT"' > /dev/null 2>&1 || true
sleep 3

# Verify disconnect
INST2_STATE_POST=$(cosmos_api "get_interface" '"INST2_INT"' 2>/dev/null \
    | jq -r '.result.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
echo "INST2_INT state after disconnect: $INST2_STATE_POST"

# ── 6. Inject Fault 2: Override TEMP3 to constant value ───────────
# Simulates previous engineer's leftover telemetry override
TEMP3_STUCK=85.0
echo "Injecting fault: overriding TEMP3 to ${TEMP3_STUCK}..."
cosmos_api "override_tlm" "\"INST\",\"HEALTH_STATUS\",\"TEMP3\",$TEMP3_STUCK" > /dev/null 2>&1 || true
sleep 2

# Verify override took effect
TEMP3_POST=$(cosmos_tlm "INST HEALTH_STATUS TEMP3" 2>/dev/null || echo "0")
echo "TEMP3 after override: $TEMP3_POST"

# ── 7. Record ground truth for verifier ───────────────────────────
cat > /tmp/${TASK_NAME}_ground_truth.json << GTEOF
{
    "faults_injected": 2,
    "inst2_int_disconnected": true,
    "temp3_override_value": $TEMP3_STUCK,
    "temp3_baseline": "$TEMP3_BASELINE",
    "inst2_initial_state": "$INST2_STATE"
}
GTEOF
chmod 644 /tmp/${TASK_NAME}_ground_truth.json

# ── 8. Create commissioning briefing on Desktop ──────────────────
cat > /home/ga/Desktop/commissioning_briefing.txt << 'BRIEFEOF'
===============================================
  THERMAL SUBSYSTEM COMMISSIONING PROCEDURE
===============================================

Satellite:  INST (HEALTH_STATUS packet)
Sensors:    TEMP1, TEMP2, TEMP3, TEMP4

NOTE: The previous shift's commissioning attempt was interrupted.
The system may be in a partially-configured state. You must audit
the system and resolve any issues before proceeding.

Procedure:
  1. Audit system state (interfaces, telemetry health, limits)
  2. Resolve any pre-existing issues found during audit
  3. Collect >= 20 temporally-spaced observations of all 4 sensors
  4. Compute per-sensor statistics: min, max, mean, stddev
  5. Calculate limits:
       YELLOW_LOW  = mean - 3 * stddev
       YELLOW_HIGH = mean + 3 * stddev
       RED_LOW     = mean - 4 * stddev
       RED_HIGH    = mean + 4 * stddev
  6. Apply limits to all 4 sensors via COSMOS
  7. Monitor >= 30 seconds to verify no false alarms
  8. Write commissioning report

Report schema (commissioning_report.json):
{
  "commissioning_target": "INST",
  "pre_commissioning_issues": [
    {
      "issue": "<description of what was found>",
      "resolution": "<what was done to fix it>"
    }
  ],
  "observations": {
    "count": <number_of_readings>,
    "duration_seconds": <time_span_of_collection>,
    "sensors": {
      "TEMP1": {"min": N, "max": N, "mean": N, "stddev": N},
      "TEMP2": {"min": N, "max": N, "mean": N, "stddev": N},
      "TEMP3": {"min": N, "max": N, "mean": N, "stddev": N},
      "TEMP4": {"min": N, "max": N, "mean": N, "stddev": N}
    }
  },
  "limits_applied": {
    "TEMP1": {"red_low": N, "yellow_low": N, "yellow_high": N, "red_high": N},
    "TEMP2": {"red_low": N, "yellow_low": N, "yellow_high": N, "red_high": N},
    "TEMP3": {"red_low": N, "yellow_low": N, "yellow_high": N, "red_high": N},
    "TEMP4": {"red_low": N, "yellow_low": N, "yellow_high": N, "red_high": N}
  },
  "verification": {
    "monitoring_duration_seconds": <N>,
    "false_alarms_detected": <count>,
    "all_sensors_nominal": true
  },
  "commissioning_status": "COMPLETE"
}
===============================================
BRIEFEOF
chown ga:ga /home/ga/Desktop/commissioning_briefing.txt

# ── 9. Ensure Firefox is running and focused ──────────────────────
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to COSMOS home
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# ── 10. Take initial screenshot ───────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_initial.png

echo "=== Thermal Commissioning Setup Complete ==="
echo ""
echo "Task: Commission the INST thermal monitoring subsystem."
echo "A briefing document is available at: /home/ga/Desktop/commissioning_briefing.txt"
echo "Output must be written to: /home/ga/Desktop/commissioning_report.json"
echo ""
