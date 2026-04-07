#!/bin/bash
# export_result.sh - Export results for Field Browser Config task
set -e

echo "=== Exporting Field Browser Config Results ==="

# 1. Take final screenshot (before killing app)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to force Preferences flush to disk
# Chromium browsers only guarantee updated Preferences file on exit
echo "Closing Edge to flush settings..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3
# Ensure it's dead
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true

# 3. Collect Data

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Helper to read JSON using Python
read_json_field() {
    python3 -c "import json, sys; 
try:
    data = json.load(open('$1'))
    print($2)
except Exception as e:
    print('')" 2>/dev/null
}

PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
BOOKMARKS_FILE="/home/ga/.config/microsoft-edge/Default/Bookmarks"
FIELD_DATA_DIR="/home/ga/Documents/FieldData"
SUMMARY_FILE="/home/ga/Desktop/field_config_summary.txt"

# Analyze Preferences
DOWNLOAD_DIR=$(read_json_field "$PREFS_FILE" "data.get('download', {}).get('default_directory', '')")
SHOW_HOME=$(read_json_field "$PREFS_FILE" "str(data.get('browser', {}).get('show_home_button', False)).lower()")
HOMEPAGE=$(read_json_field "$PREFS_FILE" "data.get('homepage', '')")
STARTUP_TYPE=$(read_json_field "$PREFS_FILE" "data.get('session', {}).get('restore_on_startup', 0)")
STARTUP_URLS=$(read_json_field "$PREFS_FILE" "json.dumps(data.get('session', {}).get('startup_urls', []))")

# Analyze Bookmarks (Look for 'Field Resources' folder)
BOOKMARKS_JSON=$(python3 << 'PYEOF'
import json, sys
try:
    with open("/home/ga/.config/microsoft-edge/Default/Bookmarks", 'r') as f:
        data = json.load(f)
    
    def find_folder(node, target_name):
        if node.get('type') == 'folder' and node.get('name') == target_name:
            return node
        if 'children' in node:
            for child in node['children']:
                res = find_folder(child, target_name)
                if res: return res
        return None

    roots = data.get('roots', {})
    found_folder = None
    for root in roots.values():
        found_folder = find_folder(root, 'Field Resources')
        if found_folder: break
    
    result = {
        "exists": found_folder is not None,
        "children": [c.get('url') for c in found_folder.get('children', [])] if found_folder else []
    }
    print(json.dumps(result))
except:
    print(json.dumps({"exists": False, "children": []}))
PYEOF
)

# Analyze Saved Files
SAVED_FILES=$(find "$FIELD_DATA_DIR" -type f -name "*.html" -o -name "*.htm" 2>/dev/null | wc -l)
FILE_DETAILS=$(find "$FIELD_DATA_DIR" -type f -printf "%f|%s|%T@\n" 2>/dev/null || echo "")

# Analyze Summary Report
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$SUMMARY_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$SUMMARY_FILE" | head -c 1000) # limit size
fi

# Analyze History (to prove pages were visited)
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
# Copy to temp to read safely
cp "$HISTORY_DB" /tmp/history_copy.db 2>/dev/null || true
HISTORY_URLS=$(sqlite3 /tmp/history_copy.db "SELECT url FROM urls ORDER BY last_visit_time DESC LIMIT 50;" 2>/dev/null || echo "")

# Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "timestamp": $CURRENT_TIME,
    "task_start": $TASK_START,
    "preferences": {
        "download_dir": "$DOWNLOAD_DIR",
        "show_home_button": $SHOW_HOME,
        "homepage": "$HOMEPAGE",
        "startup_type": $STARTUP_TYPE,
        "startup_urls": $STARTUP_URLS
    },
    "bookmarks": $BOOKMARKS_JSON,
    "files": {
        "count": $SAVED_FILES,
        "details": "$FILE_DETAILS"
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "content_preview": $(jq -n --arg content "$REPORT_CONTENT" '$content')
    },
    "history_urls": $(jq -n --arg history "$HISTORY_URLS" '$history | split("\n")')
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="