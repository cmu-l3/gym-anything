#!/bin/bash
echo "=== Setting up add_tags_to_items task ==="

# Ensure some items exist in the library (import sample data if needed)
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"

if [ -f "$ZOTERO_DB" ]; then
    ITEM_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID != 14 AND itemTypeID != 1" 2>/dev/null || echo "0")

    # If not enough items, seed the library using seed_library.py
    if [ "$ITEM_COUNT" -lt 3 ]; then
        echo "Not enough items in library ($ITEM_COUNT), seeding with ML papers..."

        # Kill Zotero before writing to SQLite (avoids database lock)
        pkill -f zotero 2>/dev/null || true
        sleep 3
        pkill -9 -f zotero 2>/dev/null || true
        sleep 2

        # Seed the library with ML papers via direct SQLite insertion
        python3 /workspace/scripts/seed_library.py --mode ml 2>&1 || echo "Warning: seed_library.py returned non-zero"

        # Verify seeding
        NEW_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID != 14 AND itemTypeID != 1" 2>/dev/null || echo "0")
        echo "Items after seeding: $NEW_COUNT"

        # Restart Zotero
        echo "Restarting Zotero..."
        sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero_restart.log 2>&1 &'
        sleep 12

        # Wait for Zotero window
        for i in $(seq 1 30); do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Zotero"; then
                echo "Zotero window appeared after ${i}s"
                break
            fi
            sleep 1
        done
    fi

    # Record initial tag count and tagged item count
    INITIAL_TAG_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(DISTINCT tagID) FROM itemTags" 2>/dev/null || echo "0")
    echo "$INITIAL_TAG_COUNT" > /tmp/initial_tag_count
    echo "Initial tag count: $INITIAL_TAG_COUNT"

    INITIAL_TAGGED_ITEMS=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(DISTINCT itemID) FROM itemTags" 2>/dev/null || echo "0")
    echo "$INITIAL_TAGGED_ITEMS" > /tmp/initial_tagged_items
    echo "Initial tagged items: $INITIAL_TAGGED_ITEMS"
else
    echo "0" > /tmp/initial_tag_count
    echo "0" > /tmp/initial_tagged_items
    echo "Zotero database not found"
fi

# Ensure Zotero window is visible and maximized
sleep 2
echo "Verifying Zotero window state..."

# Check if window exists
if ! DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
    echo "⚠ WARNING: Zotero window not found in window list!"
    echo "Attempting to restart Zotero..."
    pkill -f zotero 2>/dev/null || true
    sleep 2
    sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero_restart.log 2>&1 &'
    sleep 10
fi

# Maximize and activate
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || echo "⚠ Maximize failed"
sleep 1
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || echo "⚠ Activate failed"
sleep 1

# Take screenshot to verify state
DISPLAY=:1 import -window root /tmp/task_start_verification.png 2>/dev/null

# Verify window is now visible
if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
    echo "✓ Zotero window verified"
else
    echo "✗ CRITICAL: Zotero window still not visible!"
fi

sleep 1
echo "=== Task setup complete ==="
