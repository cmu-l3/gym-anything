#!/bin/bash
echo "=== Setting up create_backlinks_footer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Wait for TiddlyWiki server to be fully responsive
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running."
        break
    fi
    sleep 1
done

# Seed the wiki with a Zettelkasten dataset via the HTTP API
echo "Seeding Zettelkasten notes..."

curl -s -X PUT -H "Content-Type: application/json" -d '{"title": "Zettelkasten", "text": "The Zettelkasten is a note-taking method. It relies heavily on [[Evergreen Notes]] and [[Bidirectional Linking]]. Created by [[Niklas Luhmann]]."}' http://localhost:8080/recipes/default/tiddlers/Zettelkasten

curl -s -X PUT -H "Content-Type: application/json" -d '{"title": "Evergreen Notes", "text": "Evergreen notes are meant to evolve over time. They are a core component of a modern [[Zettelkasten]]. They differ from transient notes. See also [[Note-taking]]."}' http://localhost:8080/recipes/default/tiddlers/Evergreen%20Notes

curl -s -X PUT -H "Content-Type: application/json" -d '{"title": "Bidirectional Linking", "text": "Bidirectional linking allows you to see what links to the current note. This is often implemented via a Backlinks footer. Essential for a digital [[Zettelkasten]]."}' http://localhost:8080/recipes/default/tiddlers/Bidirectional%20Linking

curl -s -X PUT -H "Content-Type: application/json" -d '{"title": "Note-taking", "text": "The practice of recording information. Examples include [[Zettelkasten]] and outline methods."}' http://localhost:8080/recipes/default/tiddlers/Note-taking

curl -s -X PUT -H "Content-Type: application/json" -d '{"title": "Niklas Luhmann", "text": "A sociologist who invented the [[Zettelkasten]] method."}' http://localhost:8080/recipes/default/tiddlers/Niklas%20Luhmann

curl -s -X PUT -H "Content-Type: application/json" -d '{"title": "Orphan Note", "text": "This note has no incoming links. It is completely isolated. A backlinks footer should NOT show any heading here."}' http://localhost:8080/recipes/default/tiddlers/Orphan%20Note

sleep 2

# Save the initial HTML render of the Orphan Note to compare later (verifying conditional logic)
curl -s "http://localhost:8080/recipes/default/tiddlers/Orphan%20Note.html" > /tmp/orphan_initial.html

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Dismiss any potential dialogs and refresh page to show new content
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool key F5
sleep 3

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="