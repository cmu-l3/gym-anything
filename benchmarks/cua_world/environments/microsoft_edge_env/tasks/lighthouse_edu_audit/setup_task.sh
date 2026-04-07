#!/bin/bash
# Setup for Lighthouse Accessibility Audit task
# Cleans environment, records start time, and launches Edge.

set -e

TASK_NAME="lighthouse_edu_audit"
REPORT_PATH="/home/ga/Desktop/lighthouse_audit_report.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
BASELINE_FILE="/tmp/task_baseline_${TASK_NAME}.json"

echo "=== Setting up ${TASK_NAME} ==="

# ── STEP 1: Kill any running Edge instances ──────────────────────────────────
echo "Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# ── STEP 2: Clean up previous task artifacts ─────────────────────────────────
echo "Removing previous reports..."
rm -f "${REPORT_PATH}"

# Ensure Desktop exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# ── STEP 3: Record task start timestamp ──────────────────────────────────────
echo "Recording task start timestamp..."
date +%s > "${START_TS_FILE}"

# ── STEP 4: Record baseline history (optional but good for debugging) ────────
# We simply record that the history file exists; actual logic handles diffs
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
if [ -f "$HISTORY_DB" ]; then
    echo "History DB found at $HISTORY_DB"
else
    echo "No existing History DB (fresh profile)."
fi

# ── STEP 5: Launch Edge ──────────────────────────────────────────────────────
echo "Launching Microsoft Edge..."
# Launching with basic profile settings suitable for DevTools usage
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    about:blank \
    > /tmp/edge.log 2>&1 &"

# Wait for Edge window to appear
echo "Waiting for window..."
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Ensure window is maximized
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete for ${TASK_NAME} ==="