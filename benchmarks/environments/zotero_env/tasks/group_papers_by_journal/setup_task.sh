#!/bin/bash
# Setup for group_papers_by_journal task
# Seeds library with classic and ML papers (containing the required Nature and NeurIPS papers)

echo "=== Setting up group_papers_by_journal task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero to ensure DB is not locked ────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed Library ──────────────────────────────────────────────────────────
# Using 'all' mode to get both classic papers (contains Watson/Crick Nature paper)
# and ML papers (contains Nature and NeurIPS papers)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_ids.json 2>/tmp/seed_stderr.txt
SEED_EXIT=$?
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seed_library.py failed"
    cat /tmp/seed_stderr.txt
    exit 1
fi

# ── 3. Record Initial State ──────────────────────────────────────────────────
# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Record initial collection count (should be 0)
INITIAL_COLL_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM collections WHERE libraryID=1" 2>/dev/null || echo "0")
echo "$INITIAL_COLL_COUNT" > /tmp/initial_collection_count
echo "Initial collections: $INITIAL_COLL_COUNT"

# ── 4. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
# Use setsid to detach from shell, ensure it runs as 'ga' user
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# Wait for window
echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Zotero window found after ${i}s"
        break
    fi
    sleep 1
done
sleep 5

# Activate and maximize
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ── 5. Capture Initial Screenshot ────────────────────────────────────────────
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="