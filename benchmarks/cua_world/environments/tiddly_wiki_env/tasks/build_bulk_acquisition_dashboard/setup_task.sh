#!/bin/bash
echo "=== Setting up build_bulk_acquisition_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

WIKI_TIDDLERS="/home/ga/mywiki/tiddlers"

# Create 30 real-world book tiddlers in the AcquisitionQueue
BOOKS=(
    "1984" "To Kill a Mockingbird" "The Great Gatsby" "Pride and Prejudice" "The Catcher in the Rye"
    "The Lord of the Rings" "The Hobbit" "Fahrenheit 451" "Jane Eyre" "Animal Farm"
    "The Grapes of Wrath" "Catch-22" "Brave New World" "The Odyssey" "The Iliad"
    "Crime and Punishment" "The Brothers Karamazov" "War and Peace" "Anna Karenina" "Madame Bovary"
    "Les Miserables" "The Count of Monte Cristo" "Don Quixote" "Moby-Dick" "Frankenstein"
    "Dracula" "The Picture of Dorian Gray" "Wuthering Heights" "Great Expectations" "A Tale of Two Cities"
)

echo "Seeding 30 book tiddlers into $WIKI_TIDDLERS..."
for book in "${BOOKS[@]}"; do
    safe_title=$(echo "$book" | sed 's/[\/\\:*?"<>|]/_/g')
    cat > "$WIKI_TIDDLERS/${safe_title}.tid" << EOF
title: $book
tags: AcquisitionQueue Book
catalog-status: Pending
type: text/vnd.tiddlywiki

This is the acquisition record for the book ''$book''.
EOF
done

chown -R ga:ga "$WIKI_TIDDLERS"

# Wait for TiddlyWiki server to recognize the files and be accessible
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is open and focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="