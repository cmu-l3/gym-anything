#!/bin/bash
# Shared utilities for Juris-M (Jurism) tasks

# Get Jurism database path
get_jurism_db() {
    # Check cached path first
    if [ -f /tmp/jurism_db_path ]; then
        cat /tmp/jurism_db_path
        return
    fi
    # Search for database
    for db_path in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
        if [ -f "$db_path" ]; then
            echo "$db_path"
            return
        fi
    done
    echo ""
}

# Query Jurism database
jurism_query() {
    local query="$1"
    local db_path
    db_path=$(get_jurism_db)
    if [ -z "$db_path" ]; then
        echo ""
        return
    fi
    sqlite3 "$db_path" "$query" 2>/dev/null || echo ""
}

# Get item count (excludes system types: 1=attachment, 3=note, 31=annotation)
get_item_count() {
    jurism_query "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)"
}

# Get collection count
get_collection_count() {
    jurism_query "SELECT COUNT(*) FROM collections"
}

# Get tag count
get_tag_count() {
    jurism_query "SELECT COUNT(DISTINCT tagID) FROM itemTags"
}

# Get note count
get_note_count() {
    jurism_query "SELECT COUNT(*) FROM itemNotes"
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Find item by caseName or title (fieldID=58=caseName for cases, fieldID=1=title for articles)
find_item_by_title() {
    local title="$1"
    jurism_query "SELECT itemID FROM items JOIN itemData ON items.itemID = itemData.itemID JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE fieldID IN (1,58) AND LOWER(value) LIKE LOWER('%${title}%') LIMIT 1"
}

# Get item field value
get_item_field() {
    local item_id="$1"
    local field_id="$2"
    jurism_query "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE itemID=${item_id} AND fieldID=${field_id}"
}

# Dismiss in-app Jurism alert dialogs by pressing Return on the Jurism window.
# Jurism's "Alert" dialogs (e.g., jurisdiction config) are in-app XUL dialogs,
# NOT separate OS windows. xdotool search --name "Alert" finds nothing.
# The fix: target the Jurism window directly via its window ID.
# Args: $1 = max_seconds to loop (default: 45)
wait_and_dismiss_jurism_alerts() {
    local max_secs="${1:-45}"
    local elapsed=0
    echo "Dismissing Jurism alerts (pressing Return on Jurism window, up to ${max_secs}s)..."
    while [ "$elapsed" -lt "$max_secs" ]; do
        local wid
        wid=$(DISPLAY=:1 xdotool search --name "Jurism" 2>/dev/null | head -1)
        if [ -n "$wid" ]; then
            DISPLAY=:1 xdotool key --window "$wid" Return 2>/dev/null || true
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "Alert dismissal complete (${elapsed}s elapsed)"
}

# Ensure Jurism is running and window is visible
ensure_jurism_running() {
    if ! ps aux | grep -v grep | grep -q "[j]urism"; then
        echo "Jurism not running, starting..."
        setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_restart.log 2>&1 &'
        sleep 5
        wait_and_dismiss_jurism_alerts 45
    fi

    # Maximize and focus window
    DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
    sleep 1
}

# Inject items into Jurism database from RIS file via SQLite
# This function pre-loads legal references directly into the DB
load_legal_references_to_db() {
    local db_path
    db_path=$(get_jurism_db)
    if [ -z "$db_path" ]; then
        echo "ERROR: Cannot find Jurism database"
        return 1
    fi

    echo "Loading legal references into database: $db_path"

    # Check if already loaded (look for our specific test items)
    existing=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
    if [ "$existing" -ge 8 ]; then
        echo "Legal references already loaded ($existing items found)"
        return 0
    fi

    # Use Python script for insertion (handles libraryID/key requirements of Jurism 6)
    python3 /workspace/utils/inject_references.py "$db_path" 2>/dev/null || true

    echo "References loaded"
}
