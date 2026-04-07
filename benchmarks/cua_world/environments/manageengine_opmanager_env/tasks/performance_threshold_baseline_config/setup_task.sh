#!/bin/bash
# setup_task.sh — Configuring Performance Monitor Thresholds per Baseline Policy
# Waits for OpManager, places the policy document, and records the initial state.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Performance Threshold Baseline Config Task ==="

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
# 2. Write Policy Document to Desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/performance_baseline_policy.txt" << 'EOF'
========================================================================
  INFRASTRUCTURE PERFORMANCE BASELINE POLICY  v4.1
  Effective Date: 2024-Q4
  Issued by: Systems Engineering — Capacity Planning Team
========================================================================

SCOPE: All monitored infrastructure servers in OpManager.

PURPOSE: Replace factory-default monitoring thresholds with operationally
validated baseline values derived from 90-day traffic analysis.

SECTION 1 — CPU UTILIZATION
  • Warning Threshold:  75%
  • Critical Threshold: 90%
  Rationale: Peak CPU during batch processing regularly hits 65%.
  The 75% warning provides 10-point headroom before investigation.

SECTION 2 — MEMORY UTILIZATION
  • Warning Threshold:  80%
  • Critical Threshold: 92%
  Rationale: Application memory footprint stabilizes at ~72% under
  normal load. The 80% warning avoids false positives from JVM GC spikes.

SECTION 3 — DISK UTILIZATION (Primary/Root Volume)
  • Warning Threshold:  70%
  • Critical Threshold: 85%
  Rationale: Log rotation runs at 60% capacity. The 70% warning
  ensures early detection of runaway log growth or failed rotation.

IMPLEMENTATION NOTES:
  - Apply to the primary monitored server (localhost / 127.0.0.1)
  - All values are percentage-based
  - Changes must be saved and persisted in OpManager
  - Confirm thresholds are visible on the device's monitor detail page

APPROVAL: Signed — Director of Infrastructure Engineering
========================================================================
EOF

chown ga:ga "$DESKTOP_DIR/performance_baseline_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Performance baseline policy written to $DESKTOP_DIR/performance_baseline_policy.txt"

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date +%s > /tmp/task_start_time.txt
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_iso.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
sleep 2
take_screenshot "/tmp/task_initial_state.png" || true

echo "[setup] === Setup Complete ==="