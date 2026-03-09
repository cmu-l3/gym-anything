#!/bin/bash
# Setup for create_chronological_collections task
# Seeds 18 papers into Zotero library from mixed eras

echo "=== Setting up create_chronological_collections task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero to ensure safe DB access ────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers ────────────────────────────────────────────────────────
# Using 'all' mode to get both classic (early 20th century) and ML (21st century) papers
echo "Seeding library with 18 papers..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_ids.json 2>/tmp/seed_stderr.txt
SEED_EXIT=$?
cat /tmp/seed_stderr.txt
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seed_library.py failed"
    exit 1
fi

# ── 3. Record baseline state ──────────────────────────────────────────────
# We expect 0 collections at start
INITIAL_COLLECTION_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM collections WHERE libraryID=1" 2>/dev/null || echo "0")
echo "$INITIAL_COLLECTION_COUNT" > /tmp/initial_collection_count

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

echo "Initial collections: $INITIAL_COLLECTION_COUNT"

# ── 4. Restart Zotero ─────────────────────────────────────────────────────
echo "Restarting Zotero..."
# Use setsid to detach from shell, ensure env vars are set
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for Zotero window
echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Zotero window found after ${i}s"
        break
    fi
    sleep 1
done

sleep 5

# ── 5. Ensure window is maximized and focused ─────────────────────────────
# This is critical for the agent to see the "New Collection" button and items
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# ── 6. Capture initial screenshot ─────────────────────────────────────────
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete: create_chronological_collections ==="