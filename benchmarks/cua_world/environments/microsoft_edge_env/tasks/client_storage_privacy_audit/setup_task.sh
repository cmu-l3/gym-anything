#!/bin/bash
# setup_task.sh - Pre-task hook for client_storage_privacy_audit
# Clears history/cookies to ensure clean state and records start time.

set -e

TASK_NAME="client_storage_privacy_audit"
REPORT_FILE="/home/ga/Desktop/storage_audit_report.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill Edge ────────────────────────────────────────────────────────
echo "[1/4] Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# ── STEP 2: Clean State (History & Cookies) ──────────────────────────────────
# We delete history to ensure any visits we detect are from THIS task session.
echo "[2/4] Clearing browser history and cookies..."
rm -f "${PROFILE_DIR}/History" "${PROFILE_DIR}/History-journal"
rm -f "${PROFILE_DIR}/Cookies" "${PROFILE_DIR}/Cookies-journal"
rm -f "${PROFILE_DIR}/Web Data" "${PROFILE_DIR}/Web Data-journal"

# Clean up previous report
rm -f "${REPORT_FILE}"

# ── STEP 3: Record Timestamp ─────────────────────────────────────────────────
echo "[3/4] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Launch Edge ──────────────────────────────────────────────────────
echo "[4/4] Launching Microsoft Edge..."
# Launch with specific flags to ensure clean start and no restoration
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    about:blank \
    > /tmp/edge.log 2>&1 &"

# Wait for Edge window
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

# Take initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete for ${TASK_NAME} ==="