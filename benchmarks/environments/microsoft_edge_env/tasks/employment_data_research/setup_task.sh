#!/bin/bash
# Setup for Employment Data Research task
# Kills Edge, records baseline BLS/FRED visit counts, download count, bookmarks state,
# then launches Edge on a blank tab.

set -e

TASK_NAME="employment_data_research"
BRIEFING_FILE="/home/ga/Desktop/labor_briefing.txt"
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

# ── STEP 2: Remove any stale briefing file ───────────────────────────────────
echo "[2/5] Removing stale briefing file..."
rm -f "${BRIEFING_FILE}"

# ── STEP 3: Record task start timestamp ──────────────────────────────────────
echo "[3/5] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Record baseline history + download counts ─────────────────────────
echo "[4/5] Recording baseline counts..."

python3 << 'PYEOF'
import sqlite3, shutil, json, os, sys

history_src = "/home/ga/.config/microsoft-edge/Default/History"
history_tmp = "/tmp/task_history_baseline_edr.sqlite"
baseline_path = "/tmp/task_baseline_employment_data_research.json"

baseline = {
    "bls_count": 0, "fred_count": 0, "census_count": 0,
    "download_count": 0,
    "labor_market_data_folder_exists": False
}

if os.path.exists(history_src):
    try:
        shutil.copy2(history_src, history_tmp)
        conn = sqlite3.connect(history_tmp)
        cur = conn.cursor()
        for domain, key in [("bls.gov", "bls_count"), ("fred.stlouisfed.org", "fred_count"),
                             ("census.gov", "census_count")]:
            cur.execute("SELECT COUNT(*) FROM urls WHERE url LIKE ?", (f"%{domain}%",))
            baseline[key] = cur.fetchone()[0] or 0
        cur.execute("SELECT COUNT(*) FROM downloads")
        baseline["download_count"] = cur.fetchone()[0] or 0
        conn.close()
        os.remove(history_tmp)
    except Exception as e:
        print(f"Warning: history query failed: {e}", file=sys.stderr)

bookmarks_path = "/home/ga/.config/microsoft-edge/Default/Bookmarks"
if os.path.exists(bookmarks_path):
    try:
        with open(bookmarks_path) as f:
            bm = json.load(f)
        def has_folder(node, name):
            if node.get("type") == "folder" and node.get("name","").strip().lower() == name.lower():
                return True
            return any(has_folder(c, name) for c in node.get("children", []))
        roots = bm.get("roots", {})
        baseline["labor_market_data_folder_exists"] = any(
            has_folder(v, "Labor Market Data") for v in roots.values() if isinstance(v, dict)
        )
    except Exception as e:
        print(f"Warning: bookmarks read failed: {e}", file=sys.stderr)

with open(baseline_path, "w") as f:
    json.dump(baseline, f)

print(f"Baseline: bls={baseline['bls_count']}, fred={baseline['fred_count']}, "
      f"downloads={baseline['download_count']}, lmd_folder={baseline['labor_market_data_folder_exists']}")
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
