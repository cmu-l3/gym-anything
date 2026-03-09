#!/bin/bash
# Setup for reclassify_item_types task
# Seeds library with 18 papers, ensuring all are set to "Journal Article" initially.

echo "=== Setting up reclassify_item_types task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero for DB access ─────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed Database ─────────────────────────────────────────────────────────
echo "Seeding library..."
# Using the existing seed script in 'all' mode (18 papers)
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_log.txt 2>&1

# ── 3. Force Initial State (All items = Journal Article) ─────────────────────
# This ensures a consistent starting state where the user MUST make changes.
# itemTypeID 22 is usually 'journalArticle' in standard Zotero schemas,
# but we'll fetch the ID dynamically to be safe.

echo "Forcing all items to 'journalArticle'..."
sqlite3 "$DB" <<EOF
UPDATE items 
SET itemTypeID = (SELECT itemTypeID FROM itemTypes WHERE typeName='journalArticle')
WHERE itemTypeID NOT IN (
    SELECT itemTypeID FROM itemTypes WHERE typeName IN ('note', 'attachment', 'annotation')
);
EOF

# ── 4. Record Initial State ──────────────────────────────────────────────────
# Count how many journal articles we have (should be 18)
INITIAL_JOURNAL_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID = (SELECT itemTypeID FROM itemTypes WHERE typeName='journalArticle')" 2>/dev/null || echo "0")
echo "$INITIAL_JOURNAL_COUNT" > /tmp/initial_journal_count
echo "Initial Journal Articles: $INITIAL_JOURNAL_COUNT"

# Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# ── 5. Launch Zotero ─────────────────────────────────────────────────────────
echo "Launching Zotero..."
# Use sudo -u ga to run as user 'ga'
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

# ── 6. Initial Screenshot ────────────────────────────────────────────────────
sleep 1
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="