#!/bin/bash
echo "=== Setting up create_journal_entry task ==="

source /workspace/scripts/task_utils.sh

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Record today's date for later verification
date +%Y%m%d > /tmp/task_date
date +"%d %B %Y" > /tmp/task_date_formatted
echo "Today's date: $(cat /tmp/task_date_formatted)"

# List existing tiddlers with Journal tag
EXISTING_JOURNALS=$(find_tiddlers_with_tag "Journal")
echo "$EXISTING_JOURNALS" > /tmp/initial_journals
echo "Existing journal entries: $(echo "$EXISTING_JOURNALS" | wc -l)"

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/journal_initial.png

echo "=== Task setup complete ==="
