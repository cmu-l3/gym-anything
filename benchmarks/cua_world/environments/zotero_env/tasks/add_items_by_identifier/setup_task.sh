#!/bin/bash
# Setup for add_items_by_identifier task
# Seeds library with standard papers and records initial state

echo "=== Setting up add_items_by_identifier task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero to safely modify DB ──────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed Library ─────────────────────────────────────────────────────────
# Use 'all' mode to populate with 18 standard papers (Classic + ML)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# ── 3. Record Initial State ─────────────────────────────────────────────────
# Count bibliographic items (exclude notes=1, attachments=14)
INITIAL_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14, 28) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count
echo "Initial item count: $INITIAL_COUNT"

# Record start time for anti-gaming (verification checks items added after this)
date +%s > /tmp/task_start_time.txt

# ── 4. Restart Zotero ───────────────────────────────────────────────────────
echo "Restarting Zotero..."
# Use setsid to detach from shell, ensure it survives script exit
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# Wait for Zotero window to appear
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
        echo "✓ Zotero window detected"
        break
    fi
    sleep 1
done

# ── 5. Configure Window ─────────────────────────────────────────────────────
sleep 3
# Activate (focus)
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
# Maximize
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ── 6. Capture Evidence ─────────────────────────────────────────────────────
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="