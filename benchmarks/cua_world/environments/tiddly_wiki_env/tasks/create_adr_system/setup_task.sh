#!/bin/bash
echo "=== Setting up create_adr_system task ==="

source /workspace/scripts/task_utils.sh

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count

# Record start time
date +%s > /tmp/task_start_time.txt

# Create seed tiddlers to establish realistic context
cat > "$TIDDLER_DIR/Platform Migration Project.tid" << 'EOF'
title: Platform Migration Project
tags: Project
type: text/vnd.tiddlywiki

!! Overview
The platform migration project aims to modernize our core infrastructure from a monolithic structure to a service-oriented architecture.
EOF

cat > "$TIDDLER_DIR/Technology Radar.tid" << 'EOF'
title: Technology Radar
tags: Reference
type: text/vnd.tiddlywiki

!! Technologies under evaluation
* PostgreSQL
* RabbitMQ
* GraphQL
* Docker
EOF

# Ensure proper ownership of the newly created files
chown ga:ga "$TIDDLER_DIR"/*.tid

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Bring Firefox to the front
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot for verification
take_screenshot /tmp/adr_initial.png

echo "=== Task setup complete ==="