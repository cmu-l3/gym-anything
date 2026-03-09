#!/bin/bash
# export_result.sh - Post-task hook for add_bookmark task
# Exports bookmark data for verification

echo "=== Exporting add_bookmark task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Get initial counts
INITIAL_COUNT=$(cat /tmp/initial_bookmark_count 2>/dev/null || echo "0")
WIKIPEDIA_ALREADY_BOOKMARKED=$(cat /tmp/wikipedia_already_bookmarked 2>/dev/null || echo "false")

# Profile and database paths - check both regular and Snap Firefox locations
# Snap Firefox (used when installed via snap on Ubuntu)
SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/default.profile"
# Regular Firefox profile
REGULAR_PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"

# Find which profile has places.sqlite
if [ -f "$SNAP_PROFILE_DIR/places.sqlite" ]; then
    PROFILE_DIR="$SNAP_PROFILE_DIR"
    echo "Using Snap Firefox profile: $PROFILE_DIR"
elif [ -f "$REGULAR_PROFILE_DIR/places.sqlite" ]; then
    PROFILE_DIR="$REGULAR_PROFILE_DIR"
    echo "Using regular Firefox profile: $PROFILE_DIR"
else
    # Try to find it dynamically
    FOUND_DB=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1)
    if [ -n "$FOUND_DB" ]; then
        PROFILE_DIR=$(dirname "$FOUND_DB")
        echo "Found Firefox profile at: $PROFILE_DIR"
    else
        PROFILE_DIR="$REGULAR_PROFILE_DIR"
        echo "WARNING: Could not find places.sqlite, defaulting to: $PROFILE_DIR"
    fi
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"

# Initialize result variables
CURRENT_BOOKMARK_COUNT=0
WIKIPEDIA_BOOKMARK_FOUND="false"
BOOKMARK_URL=""
BOOKMARK_TITLE=""
BOOKMARK_FOLDER_ID=""
NEW_BOOKMARKS_ADDED=0

# We need Firefox to close or flush its database
# Try to flush by requesting Firefox to sync (soft approach)
# If that doesn't work, we copy the database

if [ -f "$PLACES_DB" ]; then
    # Copy database to avoid lock issues
    TEMP_DB="/tmp/places_export_$$.sqlite"
    cp "$PLACES_DB" "$TEMP_DB" 2>/dev/null

    if [ -f "$TEMP_DB" ]; then
        # Get current bookmark count
        CURRENT_BOOKMARK_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_bookmarks WHERE type = 1;" 2>/dev/null || echo "0")

        # Calculate new bookmarks added
        NEW_BOOKMARKS_ADDED=$((CURRENT_BOOKMARK_COUNT - INITIAL_COUNT))

        # Check for Wikipedia bookmark
        # Look for any bookmark URL containing wikipedia.org (URL-based match only)
        # Title-only matching is NOT sufficient - URL must match to prevent false positives
        # Also extract parent folder ID to verify correct location
        WIKIPEDIA_RESULT=$(sqlite3 "$TEMP_DB" "
            SELECT p.url, b.title, b.parent
            FROM moz_bookmarks b
            JOIN moz_places p ON b.fk = p.id
            WHERE b.type = 1
            AND LOWER(p.url) LIKE '%wikipedia.org%'
            LIMIT 1;
        " 2>/dev/null || echo "")

        if [ -n "$WIKIPEDIA_RESULT" ]; then
            WIKIPEDIA_BOOKMARK_FOUND="true"
            BOOKMARK_URL=$(echo "$WIKIPEDIA_RESULT" | cut -d'|' -f1)
            BOOKMARK_TITLE=$(echo "$WIKIPEDIA_RESULT" | cut -d'|' -f2)
            BOOKMARK_FOLDER_ID=$(echo "$WIKIPEDIA_RESULT" | cut -d'|' -f3)
            echo "Found Wikipedia bookmark: $BOOKMARK_URL ($BOOKMARK_TITLE) in folder $BOOKMARK_FOLDER_ID"
            # Firefox folder IDs: 1=root, 2=menu, 3=toolbar, 4=tags, 5=unfiled (other bookmarks)
            case "$BOOKMARK_FOLDER_ID" in
                2) echo "Bookmark is in Bookmarks Menu (folder 2)" ;;
                3) echo "Bookmark is in Bookmarks Toolbar (folder 3)" ;;
                5) echo "Bookmark is in Other Bookmarks (folder 5)" ;;
                *) echo "Bookmark is in folder ID: $BOOKMARK_FOLDER_ID" ;;
            esac
        fi

        # Get all bookmarks for debugging
        ALL_BOOKMARKS=$(sqlite3 "$TEMP_DB" "
            SELECT p.url, b.title
            FROM moz_bookmarks b
            JOIN moz_places p ON b.fk = p.id
            WHERE b.type = 1
            AND p.url NOT LIKE 'place:%'
            ORDER BY b.dateAdded DESC
            LIMIT 10;
        " 2>/dev/null || echo "")

        rm -f "$TEMP_DB"
    fi
else
    echo "WARNING: places.sqlite not found at $PLACES_DB"
fi

# Escape special characters for JSON
escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

BOOKMARK_URL_ESCAPED=$(escape_json "$BOOKMARK_URL")
BOOKMARK_TITLE_ESCAPED=$(escape_json "$BOOKMARK_TITLE")
ALL_BOOKMARKS_ESCAPED=$(escape_json "$ALL_BOOKMARKS")
BOOKMARK_FOLDER_ID_ESCAPED=${BOOKMARK_FOLDER_ID:-0}

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_bookmark_count": $INITIAL_COUNT,
    "current_bookmark_count": $CURRENT_BOOKMARK_COUNT,
    "new_bookmarks_added": $NEW_BOOKMARKS_ADDED,
    "wikipedia_already_bookmarked": $WIKIPEDIA_ALREADY_BOOKMARKED,
    "wikipedia_bookmark_found": $WIKIPEDIA_BOOKMARK_FOUND,
    "bookmark_url": "$BOOKMARK_URL_ESCAPED",
    "bookmark_title": "$BOOKMARK_TITLE_ESCAPED",
    "bookmark_folder_id": $BOOKMARK_FOLDER_ID_ESCAPED,
    "all_recent_bookmarks": "$ALL_BOOKMARKS_ESCAPED",
    "places_db_exists": $([ -f "$PLACES_DB" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Result exported to /tmp/task_result.json ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
