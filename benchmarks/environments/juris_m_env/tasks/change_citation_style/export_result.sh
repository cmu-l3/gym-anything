#!/bin/bash
# Export script for change_citation_style task
echo "=== Exporting change_citation_style Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/style_final.png
echo "Screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_STYLE=$(cat /tmp/initial_citation_style 2>/dev/null || echo "unknown")

# Find Jurism profile prefs.js
PREFS_JS=""
for profile_base in /home/ga/.jurism/jurism /home/ga/.zotero/zotero; do
    found=$(find "$profile_base" -maxdepth 2 -name "prefs.js" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        PREFS_JS="$found"
        break
    fi
done

STYLE_IN_PREFS="false"
CURRENT_STYLE_PREF=""
QUICK_COPY_SETTING=""

if [ -n "$PREFS_JS" ]; then
    # Check for OSCOLA in any style-related pref
    OSCOLA_IN_PREFS=$(grep -c -i "oscola" "$PREFS_JS" 2>/dev/null || echo "0")
    [ "$OSCOLA_IN_PREFS" -gt 0 ] && STYLE_IN_PREFS="true"

    # Get the quickCopy or export.lastStyle value
    QUICK_COPY_SETTING=$(grep "quickCopy\|lastStyle\|export.format" "$PREFS_JS" 2>/dev/null | tr '\n' '|' || echo "")
    echo "Quick copy prefs: $QUICK_COPY_SETTING"
    echo "OSCOLA found in prefs: $STYLE_IN_PREFS"
else
    echo "WARNING: prefs.js not found"
fi

# Also check Jurism DB settings
JURISM_DB=$(get_jurism_db)
DB_STYLE_SETTING=""
if [ -n "$JURISM_DB" ]; then
    DB_STYLE_SETTING=$(sqlite3 "$JURISM_DB" "SELECT value FROM settings WHERE setting LIKE '%style%' OR setting LIKE '%cite%' OR setting LIKE '%export%'" 2>/dev/null | tr '\n' '|' || echo "")
    echo "DB style settings: $DB_STYLE_SETTING"
fi

# Escape for JSON
QUICK_COPY_ESC=$(echo "$QUICK_COPY_SETTING" | sed 's/"/\\"/g' | tr '\n' ' ')
INITIAL_STYLE_ESC=$(echo "$INITIAL_STYLE" | sed 's/"/\\"/g')

cat > /tmp/change_citation_style_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_style": "$INITIAL_STYLE_ESC",
    "oscola_in_prefs": $STYLE_IN_PREFS,
    "quick_copy_setting": "$QUICK_COPY_ESC",
    "prefs_js_path": "${PREFS_JS:-not_found}",
    "screenshot_path": "/tmp/style_final.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/change_citation_style_result.json 2>/dev/null || true
echo "Result saved to /tmp/change_citation_style_result.json"
cat /tmp/change_citation_style_result.json
echo "=== Export Complete ==="
