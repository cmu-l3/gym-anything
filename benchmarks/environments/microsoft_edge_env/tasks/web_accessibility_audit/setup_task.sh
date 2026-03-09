#!/bin/bash
# Setup for Web Accessibility Audit task
# Records baseline browser history for ssa.gov and irs.gov,
# removes any pre-existing report, then launches Edge on a blank tab.

set -e

TASK_NAME="web_accessibility_audit"
REPORT_FILE="/home/ga/Desktop/accessibility_audit_report.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
BASELINE_FILE="/tmp/task_baseline_${TASK_NAME}.json"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill any running Edge instances ──────────────────────────────────
echo "[1/5] Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 1

# ── STEP 2: Remove any stale output files ────────────────────────────────────
echo "[2/5] Removing stale report file..."
rm -f "${REPORT_FILE}"

# ── STEP 3: Record task start timestamp ──────────────────────────────────────
echo "[3/5] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Record baseline browser history counts ───────────────────────────
echo "[4/5] Recording baseline history counts for ssa.gov and irs.gov..."

python3 << 'PYEOF'
import sqlite3, shutil, json, os, sys

history_src = "/home/ga/.config/microsoft-edge/Default/History"
history_tmp = "/tmp/task_history_baseline_waa.sqlite"
baseline_path = "/tmp/task_baseline_web_accessibility_audit.json"

baseline = {"ssa_count": 0, "irs_count": 0}

if os.path.exists(history_src):
    try:
        shutil.copy2(history_src, history_tmp)
        conn = sqlite3.connect(history_tmp)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%ssa.gov%'")
        baseline["ssa_count"] = cur.fetchone()[0] or 0
        cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%irs.gov%'")
        baseline["irs_count"] = cur.fetchone()[0] or 0
        conn.close()
        os.remove(history_tmp)
    except Exception as e:
        print(f"Warning: could not read history: {e}", file=sys.stderr)

with open(baseline_path, "w") as f:
    json.dump(baseline, f)

print(f"Baseline: ssa.gov={baseline['ssa_count']} visits, irs.gov={baseline['irs_count']} visits")
PYEOF

# ── STEP 5: Launch Edge and take start screenshot ─────────────────────────────
echo "[5/5] Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    > /tmp/edge.log 2>&1 &"

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

DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/${TASK_NAME}_start.png"

echo "=== Setup complete for ${TASK_NAME} ==="
echo "Audit targets: https://www.ssa.gov and https://www.irs.gov"
echo "Report expected at: ${REPORT_FILE}"
