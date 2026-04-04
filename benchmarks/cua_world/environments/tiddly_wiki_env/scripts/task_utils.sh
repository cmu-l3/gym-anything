#!/bin/bash
# Shared utilities for TiddlyWiki tasks

WIKI_DIR="/home/ga/mywiki"
TIDDLER_DIR="$WIKI_DIR/tiddlers"
TW_URL="http://localhost:8080"

# Take screenshot using ImageMagick (more reliable than scrot)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Count .tid files in tiddlers directory (excludes system tiddlers starting with $__)
count_user_tiddlers() {
    find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' 2>/dev/null | wc -l
}

# Check if a tiddler exists by title (case-insensitive filename search)
tiddler_exists() {
    local title="$1"
    local sanitized=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g')
    if [ -f "$TIDDLER_DIR/${sanitized}.tid" ]; then
        echo "true"
        return 0
    fi
    # Try case-insensitive search
    local found=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "true"
        return 0
    fi
    echo "false"
    return 1
}

# Get tiddler content by title
get_tiddler_content() {
    local title="$1"
    local sanitized=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g')
    local file="$TIDDLER_DIR/${sanitized}.tid"
    if [ ! -f "$file" ]; then
        # Try case-insensitive search
        file=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" 2>/dev/null | head -1)
    fi
    if [ -f "$file" ]; then
        cat "$file"
    fi
}

# Get a specific field value from a .tid file
get_tiddler_field() {
    local title="$1"
    local field="$2"
    local content=$(get_tiddler_content "$title")
    if [ -n "$content" ]; then
        echo "$content" | grep -i "^${field}:" | head -1 | sed "s/^${field}: *//i"
    fi
}

# Get the text body of a tiddler (everything after the blank line)
get_tiddler_text() {
    local title="$1"
    local sanitized=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g')
    local file="$TIDDLER_DIR/${sanitized}.tid"
    if [ ! -f "$file" ]; then
        file=$(find "$TIDDLER_DIR" -maxdepth 1 -iname "${sanitized}.tid" 2>/dev/null | head -1)
    fi
    if [ -f "$file" ]; then
        # Text starts after the first blank line
        awk '/^$/{found=1; next} found{print}' "$file"
    fi
}

# List all user tiddler titles
list_tiddler_titles() {
    find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -exec grep -l "^title:" {} \; 2>/dev/null | while IFS= read -r f; do
        grep "^title:" "$f" | head -1 | sed 's/^title: *//'
    done
}

# Find tiddlers with a specific tag
find_tiddlers_with_tag() {
    local tag="$1"
    find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -exec grep -li "^tags:.*${tag}" {} \; 2>/dev/null | while IFS= read -r f; do
        grep "^title:" "$f" | head -1 | sed 's/^title: *//'
    done
}

# Find newest tiddler (by file modification time)
find_newest_tiddler() {
    ls -t "$TIDDLER_DIR"/*.tid 2>/dev/null | head -1
}

# Escape string for JSON (handles backslash, quotes, newlines, tabs, and dollar signs)
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//\$/\\\$}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# Write JSON result to file safely
write_result_json() {
    local json_content="$1"
    local output_file="$2"

    TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
    echo "$json_content" > "$TEMP_JSON"

    rm -f "$output_file" 2>/dev/null || sudo rm -f "$output_file" 2>/dev/null || true
    cp "$TEMP_JSON" "$output_file" 2>/dev/null || sudo cp "$TEMP_JSON" "$output_file"
    chmod 666 "$output_file" 2>/dev/null || sudo chmod 666 "$output_file" 2>/dev/null || true
    rm -f "$TEMP_JSON"
}
