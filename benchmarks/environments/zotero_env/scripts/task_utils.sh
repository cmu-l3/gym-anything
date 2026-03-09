#!/bin/bash
# Shared utilities for Zotero tasks

# Get Zotero database path
get_zotero_db() {
    echo "/home/ga/Zotero/zotero.sqlite"
}

# Query Zotero database
zotero_query() {
    local query="$1"
    local db_path=$(get_zotero_db)
    sqlite3 "$db_path" "$query" 2>/dev/null || echo ""
}

# Get item count
get_item_count() {
    zotero_query "SELECT COUNT(*) FROM items WHERE itemTypeID != 14 AND itemTypeID != 1"
}

# Get collection count
get_collection_count() {
    zotero_query "SELECT COUNT(*) FROM collections"
}

# Get tag count
get_tag_count() {
    zotero_query "SELECT COUNT(DISTINCT tagID) FROM itemTags"
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# Find item by title
find_item_by_title() {
    local title="$1"
    zotero_query "SELECT itemID FROM items JOIN itemData ON items.itemID = itemData.itemID JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE fieldID=110 AND LOWER(value) LIKE LOWER('%${title}%')"
}

# Get item field value
get_item_field() {
    local item_id="$1"
    local field_id="$2"
    zotero_query "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE itemID=${item_id} AND fieldID=${field_id}"
}
