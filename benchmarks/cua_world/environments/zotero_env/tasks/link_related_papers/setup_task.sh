#!/bin/bash
# Setup for link_related_papers task
# Seeds library and ensures no existing relations exist

echo "=== Setting up link_related_papers task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers ───────────────────────────────────────────────────────────
echo "Seeding library with 18 papers..."
# This script populates items, creators, etc.
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_output.txt 2>/tmp/seed_error.txt
if [ $? -ne 0 ]; then
    echo "ERROR: Seeding failed"
    cat /tmp/seed_error.txt
    exit 1
fi

# ── 3. Clean existing relations (Ensure start state is empty) ────────────────
echo "Clearing any existing item relations..."
sqlite3 "$DB" "DELETE FROM itemRelations;" 2>/dev/null || true
sqlite3 "$DB" "VACUUM;" 2>/dev/null || true

# ── 4. Record Baseline ───────────────────────────────────────────────────────
INITIAL_RELATION_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM itemRelations" 2>/dev/null || echo "0")
echo "$INITIAL_RELATION_COUNT" > /tmp/initial_relation_count
date +%s > /tmp/task_start_time

echo "Initial relation count: $INITIAL_RELATION_COUNT"

# ── 5. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
# Use setsid to detach from shell, ensure it keeps running
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

echo "Waiting for Zotero window..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Window found after ${i}s"
        break
    fi
    sleep 1
done

# Give it a moment to fully render
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# ── 6. Initial Screenshot ────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete: link_related_papers ==="