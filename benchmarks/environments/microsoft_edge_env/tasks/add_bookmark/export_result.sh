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

# Profile and bookmarks file path
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
BOOKMARKS_FILE="$PROFILE_DIR/Bookmarks"

echo "Checking bookmarks file: $BOOKMARKS_FILE"

# Initialize result variables
CURRENT_BOOKMARK_COUNT=0
WIKIPEDIA_BOOKMARK_FOUND="false"
BOOKMARK_URL=""
BOOKMARK_TITLE=""
BOOKMARK_FOLDER=""
NEW_BOOKMARKS_ADDED=0
BOOKMARKS_FILE_EXISTS="false"

if [ -f "$BOOKMARKS_FILE" ]; then
    BOOKMARKS_FILE_EXISTS="true"
    echo "Bookmarks file found"

    # Parse bookmarks using Python
    BOOKMARK_DATA=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/.config/microsoft-edge/Default/Bookmarks", 'r') as f:
        data = json.load(f)

    def extract_all_bookmarks(node, path=''):
        results = []
        if node.get('type') == 'url':
            results.append({
                'name': node.get('name', ''),
                'url': node.get('url', ''),
                'folder': path
            })
        elif node.get('type') == 'folder':
            new_path = path + '/' + node.get('name', '') if path else node.get('name', '')
            for child in node.get('children', []):
                results.extend(extract_all_bookmarks(child, new_path))
        return results

    all_bookmarks = []
    for root_name, root_node in data.get('roots', {}).items():
        if isinstance(root_node, dict):
            all_bookmarks.extend(extract_all_bookmarks(root_node, root_name))

    # Find Wikipedia bookmarks (check for duplicates)
    wikipedia_bookmarks = []
    for bm in all_bookmarks:
        if 'wikipedia.org' in bm['url'].lower():
            wikipedia_bookmarks.append(bm)

    # Use first Wikipedia bookmark found for compatibility
    wikipedia_bookmark = wikipedia_bookmarks[0] if wikipedia_bookmarks else None

    output = {
        'total_count': len(all_bookmarks),
        'wikipedia_found': wikipedia_bookmark is not None,
        'wikipedia_url': wikipedia_bookmark['url'] if wikipedia_bookmark else '',
        'wikipedia_title': wikipedia_bookmark['name'] if wikipedia_bookmark else '',
        'wikipedia_folder': wikipedia_bookmark['folder'] if wikipedia_bookmark else '',
        'wikipedia_bookmark_count': len(wikipedia_bookmarks),
        'wikipedia_bookmarks': wikipedia_bookmarks,
        'recent_bookmarks': [{'name': b['name'], 'url': b['url'], 'folder': b['folder']} for b in all_bookmarks[-10:]]
    }

    print(json.dumps(output))
except Exception as e:
    print(json.dumps({
        'total_count': 0,
        'wikipedia_found': False,
        'wikipedia_url': '',
        'wikipedia_title': '',
        'wikipedia_folder': '',
        'recent_bookmarks': [],
        'error': str(e)
    }))
PYEOF
)

    # Parse Python output
    CURRENT_BOOKMARK_COUNT=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('total_count', 0))")
    WIKIPEDIA_BOOKMARK_FOUND=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print('true' if d.get('wikipedia_found') else 'false')")
    BOOKMARK_URL=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('wikipedia_url', ''))")
    BOOKMARK_TITLE=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('wikipedia_title', ''))")
    BOOKMARK_FOLDER=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('wikipedia_folder', ''))")
    WIKIPEDIA_BOOKMARK_COUNT=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('wikipedia_bookmark_count', 0))")
    RECENT_BOOKMARKS=$(echo "$BOOKMARK_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d.get('recent_bookmarks', [])))")

    # Calculate new bookmarks added
    NEW_BOOKMARKS_ADDED=$((CURRENT_BOOKMARK_COUNT - INITIAL_COUNT))

    if [ "$WIKIPEDIA_BOOKMARK_FOUND" = "true" ]; then
        echo "Found Wikipedia bookmark: $BOOKMARK_URL ($BOOKMARK_TITLE) in folder $BOOKMARK_FOLDER"
    fi
else
    echo "WARNING: Bookmarks file not found at $BOOKMARKS_FILE"
    RECENT_BOOKMARKS="[]"
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
BOOKMARK_FOLDER_ESCAPED=$(escape_json "$BOOKMARK_FOLDER")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_bookmark_count": $INITIAL_COUNT,
    "current_bookmark_count": $CURRENT_BOOKMARK_COUNT,
    "new_bookmarks_added": $NEW_BOOKMARKS_ADDED,
    "wikipedia_already_bookmarked": $WIKIPEDIA_ALREADY_BOOKMARKED,
    "wikipedia_bookmark_found": $WIKIPEDIA_BOOKMARK_FOUND,
    "wikipedia_bookmark_count": $WIKIPEDIA_BOOKMARK_COUNT,
    "bookmark_url": "$BOOKMARK_URL_ESCAPED",
    "bookmark_title": "$BOOKMARK_TITLE_ESCAPED",
    "bookmark_folder": "$BOOKMARK_FOLDER_ESCAPED",
    "recent_bookmarks": $RECENT_BOOKMARKS,
    "bookmarks_file_exists": $BOOKMARKS_FILE_EXISTS,
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
