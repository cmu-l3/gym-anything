#!/bin/bash
echo "=== Setting up build_automated_release_notes task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

TIDDLERS_DIR="/home/ga/mywiki/tiddlers"
mkdir -p "$TIDDLERS_DIR"

echo "Seeding Pull Request tiddlers..."

# Seed PR 1: Feature (v18.2.0)
cat > "$TIDDLERS_DIR/PR_1.tid" << 'EOF'
title: Add onRecoverableError option
tags: PR Feature
target-release: v18.2.0
author: @acdlite

Adds the new root option for hydration errors.
EOF

# Seed PR 2: Bug (v18.2.0)
cat > "$TIDDLERS_DIR/PR_2.tid" << 'EOF'
title: Fix hydration mismatch with useId
tags: PR Bug
target-release: v18.2.0
author: @danabramov

Fixes a critical mismatch bug during SSR hydration.
EOF

# Seed PR 3: Warning (v18.2.0)
cat > "$TIDDLERS_DIR/PR_3.tid" << 'EOF'
title: Deprecate renderToNodeStream
tags: PR Warning
target-release: v18.2.0
author: @sebmarkbage

Warns users that renderToNodeStream is being phased out.
EOF

# Seed PR 4: Feature (v18.3.0 - Should NOT show up in v18.2.0)
cat > "$TIDDLERS_DIR/PR_4.tid" << 'EOF'
title: Support Promise as a child
tags: PR Feature
target-release: v18.3.0
author: @acdlite

Allows rendering Promises directly in React components.
EOF

# Seed PR 5: Bug (v18.3.0)
cat > "$TIDDLERS_DIR/PR_5.tid" << 'EOF'
title: Fix memory leak in useEffect
tags: PR Bug
target-release: v18.3.0
author: @gnoff

Fixes an edge case memory leak in StrictMode.
EOF

chown -R ga:ga "$TIDDLERS_DIR"

# Restart TiddlyWiki to ensure it registers the seeded files
echo "Restarting TiddlyWiki server..."
pkill -f tiddlywiki 2>/dev/null || true
sleep 2

su - ga -c "cd /home/ga/mywiki && nohup tiddlywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server to start
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is up"
        break
    fi
    sleep 1
done

# Ensure Firefox is focused and maximized
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="