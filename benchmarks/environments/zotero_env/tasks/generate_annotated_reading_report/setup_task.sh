#!/bin/bash
echo "=== Setting up generate_annotated_reading_report task ==="

DB="/home/ga/Zotero/zotero.sqlite"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up previous artifacts
rm -f "$DOCS_DIR/ai_seminar_report.html"
mkdir -p "$DOCS_DIR"

# 2. Stop Zotero to safely manipulate DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 3. Seed library with classic papers (ensure required papers exist)
echo "Seeding library..."
# Check if seeding needed
ITEM_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,14)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 10 ]; then
    python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_log.txt 2>&1
else
    echo "Library already seeded."
fi

# 4. Remove the specific collection if it already exists (from previous run)
sqlite3 "$DB" "DELETE FROM collections WHERE collectionName='AI History Seminar';" 2>/dev/null
# Remove the note if it exists
sqlite3 "$DB" "DELETE FROM itemNotes WHERE note LIKE '%Essential reading: Discusses the Imitation Game%';" 2>/dev/null

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

# 7. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# 8. Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 9. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="