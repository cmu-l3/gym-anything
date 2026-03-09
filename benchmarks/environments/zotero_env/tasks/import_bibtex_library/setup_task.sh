#!/bin/bash
echo "=== Setting up import_bibtex_library task ==="

# Copy BibTeX file to Documents folder
mkdir -p /home/ga/Documents
cp /workspace/assets/sample_data/classic_papers.bib /home/ga/Documents/
chown ga:ga /home/ga/Documents/classic_papers.bib

# Record initial item count in Zotero
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"

if [ -f "$ZOTERO_DB" ]; then
    # Count items (excluding notes and attachments: itemTypeID 1=note, 14=attachment)
    INITIAL_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID != 14 AND itemTypeID != 1" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_item_count
    echo "Initial item count: $INITIAL_COUNT"
else
    echo "0" > /tmp/initial_item_count
    echo "Zotero database not found, starting from 0"
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
