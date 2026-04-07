#!/bin/bash
echo "=== Setting up configure_wiki_identity_and_homepage task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create some seed tiddlers about Kafka so the wiki isn't completely empty
cat > /home/ga/mywiki/tiddlers/Broker.tid << 'EOF'
title: Broker
tags: Concept
type: text/vnd.tiddlywiki

A Kafka broker is a server that stores and serves events.
EOF

cat > /home/ga/mywiki/tiddlers/Topic.tid << 'EOF'
title: Topic
tags: Concept
type: text/vnd.tiddlywiki

A topic is a category or feed name to which records are published.
EOF

chown ga:ga /home/ga/mywiki/tiddlers/*.tid

# Make sure TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="