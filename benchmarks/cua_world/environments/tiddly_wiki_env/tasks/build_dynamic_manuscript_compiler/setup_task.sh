#!/bin/bash
echo "=== Setting up build_dynamic_manuscript_compiler task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

WIKI_DIR="/home/ga/mywiki"
TIDDLER_DIR="$WIKI_DIR/tiddlers"
mkdir -p "$TIDDLER_DIR"

# Create seed tiddlers representing chapters
cat > "$TIDDLER_DIR/Chapter 1_ The Arrival.tid" << 'EOF'
created: 20231012141200000
modified: 20231012141200000
tags: Chapter
title: Chapter 1: The Arrival
status: final
type: text/vnd.tiddlywiki

The ship landed at dawn. The air was thick with the smell of ozone and alien flora. Captain Vance stepped onto the ramp, realizing immediately that the coordinates were wrong.
EOF

cat > "$TIDDLER_DIR/Chapter 2_ The Discovery.tid" << 'EOF'
created: 20231012141500000
modified: 20231012141500000
tags: Chapter
title: Chapter 2: The Discovery
status: draft
type: text/vnd.tiddlywiki

They found the artifact buried deep within the crystalline caves. It hummed with a low, vibrating energy that made their teeth ache. Vance reached out to touch it, hesitating only for a second.
EOF

cat > "$TIDDLER_DIR/Chapter 3_ The Betrayal.tid" << 'EOF'
created: 20231012142000000
modified: 20231012142000000
tags: Chapter
title: Chapter 3: The Betrayal
status: outline
type: text/vnd.tiddlywiki

* Vance touches the artifact and experiences a vision.
* Crew member Elara pulls a blaster on him.
* Reveal: Elara has been working for the Syndicate all along.
* They are trapped in the cave as the entrance collapses.
EOF

chown -R ga:ga "$TIDDLER_DIR"

# Wait for TiddlyWiki to detect new files
sleep 3

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="