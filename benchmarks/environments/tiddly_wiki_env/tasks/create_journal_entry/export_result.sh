#!/bin/bash
echo "=== Exporting create_journal_entry result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/journal_final.png

INITIAL_COUNT=$(cat /tmp/initial_tiddler_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)
TODAY=$(cat /tmp/task_date 2>/dev/null || date +%Y%m%d)

# Find new tiddlers with Journal tag
JOURNAL_FOUND="false"
JOURNAL_TITLE=""
JOURNAL_TAGS=""
JOURNAL_TEXT=""
WORD_COUNT=0
HAS_DATE_IN_TITLE="false"
HAS_JOURNAL_TAG="false"

# Search for new journal tiddlers (files newer than the initial count marker)
# Use while read loop to handle filenames with spaces
while IFS= read -r f; do
    [ -z "$f" ] && continue
    TITLE=$(grep "^title:" "$f" | head -1 | sed 's/^title: *//')
    TAGS=$(grep "^tags:" "$f" | head -1 | sed 's/^tags: *//')

    # Check if this is a journal entry (has Journal tag or date-like title)
    IS_JOURNAL="false"
    echo "$TAGS" | grep -qi "journal" && IS_JOURNAL="true"

    # Check if title contains a date pattern
    TITLE_HAS_DATE="false"
    # Various date patterns: YYYYMMDD, DD Month YYYY, YYYY-MM-DD, Month DD YYYY, "February 11, 2026"
    if echo "$TITLE" | grep -qE "[0-9]{4}[/-]?[0-9]{2}[/-]?[0-9]{2}|[0-9]{1,2}(st|nd|rd|th)? [A-Z][a-z]+ [0-9]{4}|[A-Z][a-z]+ [0-9]{1,2},? [0-9]{4}"; then
        TITLE_HAS_DATE="true"
    fi

    if [ "$IS_JOURNAL" = "true" ] || [ "$TITLE_HAS_DATE" = "true" ]; then
        JOURNAL_FOUND="true"
        JOURNAL_TITLE="$TITLE"
        JOURNAL_TAGS="$TAGS"
        JOURNAL_TEXT=$(awk '/^$/{found=1; next} found{print}' "$f")
        WORD_COUNT=$(echo "$JOURNAL_TEXT" | wc -w)
        HAS_DATE_IN_TITLE="$TITLE_HAS_DATE"
        echo "$TAGS" | grep -qi "journal" && HAS_JOURNAL_TAG="true"
        break
    fi
done < <(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -newer /tmp/initial_tiddler_count 2>/dev/null)

# If no journal found yet, check any new tiddler (stricter: require Journal tag)
if [ "$JOURNAL_FOUND" = "false" ]; then
    NEWEST=$(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -newer /tmp/initial_tiddler_count 2>/dev/null | head -1)
    if [ -n "$NEWEST" ] && [ -f "$NEWEST" ]; then
        TITLE=$(grep "^title:" "$NEWEST" | head -1 | sed 's/^title: *//')
        TAGS=$(grep "^tags:" "$NEWEST" | head -1 | sed 's/^tags: *//')
        TEXT=$(awk '/^$/{found=1; next} found{print}' "$NEWEST")
        WC=$(echo "$TEXT" | wc -w)

        echo "$TAGS" | grep -qi "journal" && HAS_JOURNAL_TAG="true"

        # Only accept fallback if it has the Journal tag (prevents any random tiddler from matching)
        if [ "$HAS_JOURNAL_TAG" = "true" ]; then
            JOURNAL_FOUND="true"
            JOURNAL_TITLE="$TITLE"
            JOURNAL_TAGS="$TAGS"
            JOURNAL_TEXT="$TEXT"
            WORD_COUNT=$WC
        fi
    fi
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    # Check for any new save dispatches after setup
    if grep -qi "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        # Look for date-like or journal-like entries in save log
        if grep -iE "Dispatching 'save' task:.*(january|february|march|april|may|june|july|august|september|october|november|december|journal|[0-9]{4})" /home/ga/tiddlywiki.log 2>/dev/null; then
            GUI_SAVE_DETECTED="true"
        fi
    fi
fi

ESCAPED_TITLE=$(json_escape "$JOURNAL_TITLE")
ESCAPED_TAGS=$(json_escape "$JOURNAL_TAGS")
ESCAPED_TEXT=$(json_escape "$JOURNAL_TEXT")

JSON_RESULT=$(cat << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "journal_found": $JOURNAL_FOUND,
    "journal_title": "$ESCAPED_TITLE",
    "journal_tags": "$ESCAPED_TAGS",
    "word_count": $WORD_COUNT,
    "has_date_in_title": $HAS_DATE_IN_TITLE,
    "has_journal_tag": $HAS_JOURNAL_TAG,
    "today_date": "$TODAY",
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/create_journal_result.json"

echo "Result saved to /tmp/create_journal_result.json"
cat /tmp/create_journal_result.json
echo "=== Export complete ==="
