#!/bin/bash
set -e

echo "=== Setting up flashcard system task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count.txt
echo "Initial user tiddler count: $INITIAL_COUNT"

# Verify no flashcard tiddlers already exist (ensure clean slate)
for title in "Beta-Blockers Mechanism" "ACE Inhibitor Side Effects" "Warfarin Interactions" "Statin Mechanism" "Metformin Contraindication" "Pharmacology Deck"; do
    sanitized=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g')
    if [ -f "$TIDDLER_DIR/${sanitized}.tid" ]; then
        echo "Removing pre-existing tiddler: $title"
        rm -f "$TIDDLER_DIR/${sanitized}.tid"
    fi
done

# Restart TiddlyWiki server to ensure a clean state
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "Restarting TiddlyWiki server..."
    pkill -f "tiddlywiki.*listen" 2>/dev/null || true
    sleep 2
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    sleep 5
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Refresh browser to ensure state matches disk
DISPLAY=:1 xdotool key F5
sleep 3

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Flashcard system task setup complete ==="