#!/bin/bash
echo "=== Setting up search_email task ==="

source /workspace/scripts/task_utils.sh

# Ensure Dovecot IMAP is running
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true
sleep 2

# Ensure BlueMail is running (don't kill existing — preserves account config)
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for BlueMail window to appear
wait_for_bluemail_window 60

# Maximize the window
sleep 3
maximize_bluemail

# Record baseline - which emails contain the search keyword
SEARCH_KEYWORD="Sequences Window"
MATCHING_COUNT=0
if [ -d "$IMPORT_DIR" ]; then
    for eml_file in "$IMPORT_DIR"/*; do
        if [ -f "$eml_file" ]; then
            if grep -ql "$SEARCH_KEYWORD" "$eml_file" 2>/dev/null; then
                MATCHING_COUNT=$((MATCHING_COUNT + 1))
            fi
        fi
    done
fi
echo "$MATCHING_COUNT" > /tmp/initial_matching_count
echo "Emails matching '$SEARCH_KEYWORD': $MATCHING_COUNT"

# Take initial screenshot
take_screenshot /tmp/bluemail_task_start.png

echo "=== search_email task setup complete ==="
