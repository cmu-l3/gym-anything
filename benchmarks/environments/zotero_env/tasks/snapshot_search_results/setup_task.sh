#!/bin/bash
# Setup for snapshot_search_results task
# Seeds library with classic papers (containing "Theory") and ML papers (distractors)

set -e
echo "=== Setting up snapshot_search_results task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero for DB seeding ───────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed Data ────────────────────────────────────────────────────────────
# We use 'all' mode which includes Classic papers (Shannon, Church, Turing)
# Several have 'Theory' in the title:
# - "A Mathematical Theory of Communication"
# - "The Mathematical Theory of Communication"
# - "An Unsolvable Problem of Elementary Number Theory"
# Distractors: "Computing Machinery and Intelligence", "Attention Is All You Need", etc.
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed.log 2>&1

# ── 3. Record Start Time & Initial State ────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# Verify we have the expected data in the DB before starting
echo "Verifying seed data..."
EXPECTED_COUNT=$(sqlite3 "$DB" "
    SELECT COUNT(*) FROM items i
    JOIN itemData d ON i.itemID = d.itemID
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 1 
    AND i.itemTypeID NOT IN (1, 14) 
    AND v.value LIKE '%Theory%';" 2>/dev/null || echo "0")

echo "Found $EXPECTED_COUNT items with 'Theory' in title (Ground Truth)"
echo "$EXPECTED_COUNT" > /tmp/expected_count.txt

# ── 4. Restart Zotero ───────────────────────────────────────────────────────
echo "Restarting Zotero..."
# Use setsid to detach from shell, ensure env vars are set
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="