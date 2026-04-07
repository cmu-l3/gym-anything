#!/bin/bash
# Setup for TLS Certificate Audit task
# Kills Edge, records start timestamp, and ensures a clean state.

set -e

TASK_NAME="tls_certificate_audit"
REPORT_FILE="/home/ga/Desktop/tls_audit_report.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill any running Edge instances ──────────────────────────────────
echo "[1/4] Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# ── STEP 2: Remove any stale report files ────────────────────────────────────
echo "[2/4] Removing stale report file..."
rm -f "${REPORT_FILE}"

# ── STEP 3: Record task start timestamp ──────────────────────────────────────
echo "[3/4] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Launch Edge and take start screenshot ─────────────────────────────
echo "[4/4] Launching Microsoft Edge..."
# Launch with specific flags to ensure clean session but allow DevTools
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for Edge window to appear
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
sleep 3

# Focus the window
DISPLAY=:1 wmctrl -a "Microsoft Edge" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/${TASK_NAME}_start.png"

echo "=== Setup complete for ${TASK_NAME} ==="