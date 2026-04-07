#!/bin/bash
echo "=== Setting up build_dynamic_reading_tracker task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Pre-seed the wiki with the 4 specific Book tiddlers
echo "Creating pre-seeded Book tiddlers..."

cat > "$TIDDLER_DIR/The Dispossessed.tid" << 'EOF'
title: The Dispossessed
tags: Book
author: Ursula K. Le Guin
pages_read: 150
total_pages: 387

A brilliant science fiction novel exploring anarchism and capitalism.
EOF

cat > "$TIDDLER_DIR/Dune.tid" << 'EOF'
title: Dune
tags: Book
author: Frank Herbert
pages_read: 412
total_pages: 896

A masterpiece of ecological science fiction.
EOF

cat > "$TIDDLER_DIR/Neuromancer.tid" << 'EOF'
title: Neuromancer
tags: Book
author: William Gibson
pages_read: 271
total_pages: 271

The defining novel of the cyberpunk genre.
EOF

cat > "$TIDDLER_DIR/Foundation.tid" << 'EOF'
title: Foundation
tags: Book
author: Isaac Asimov
pages_read: 45
total_pages: 255

The fall of the Galactic Empire and the effort to save human knowledge.
EOF

chown ga:ga "$TIDDLER_DIR"/*.tid

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Refresh the browser to ensure new seeded tiddlers appear
DISPLAY=:1 xdotool key F5
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="