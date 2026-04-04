#!/bin/bash
# Setup for DevTools Network Performance Audit task
# Kills Edge, records baseline visit counts for bbc.com/reuters.com/theguardian.com,
# removes any pre-existing report, then launches Edge on a blank tab.

set -e

TASK_NAME="devtools_network_audit"
REPORT_FILE="/home/ga/Desktop/network_audit_report.txt"
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
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

# ── STEP 2: Remove any stale report files ────────────────────────────────────
echo "[2/5] Removing stale report file..."
rm -f "${REPORT_FILE}"

# ── STEP 3: Record task start timestamp ──────────────────────────────────────
echo "[3/5] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Record baseline browser history counts ───────────────────────────
echo "[4/5] Recording baseline history counts..."

python3 << 'PYEOF'
import sqlite3, shutil, json, os, sys

history_src = "/home/ga/.config/microsoft-edge/Default/History"
history_tmp = "/tmp/task_history_baseline_dna.sqlite"
baseline_path = "/tmp/task_baseline_devtools_network_audit.json"

baseline = {"bbc_count": 0, "reuters_count": 0, "guardian_count": 0}

if os.path.exists(history_src):
    try:
        shutil.copy2(history_src, history_tmp)
        conn = sqlite3.connect(history_tmp)
        cur = conn.cursor()
        for domain, key in [("bbc.com", "bbc_count"), ("reuters.com", "reuters_count"),
                             ("theguardian.com", "guardian_count")]:
            cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE ?", (f"%{domain}%",))
            baseline[key] = cur.fetchone()[0] or 0
        conn.close()
        os.remove(history_tmp)
    except Exception as e:
        print(f"Warning: could not read history: {e}", file=sys.stderr)

with open(baseline_path, "w") as f:
    json.dump(baseline, f)

print(f"Baseline: bbc={baseline['bbc_count']}, reuters={baseline['reuters_count']}, guardian={baseline['guardian_count']}")
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

# Take initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/${TASK_NAME}_start.png"

echo "=== Setup complete for ${TASK_NAME} ==="
