#!/bin/bash
echo "=== Setting up build_interactive_cli_generator task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Ensure TiddlyWiki is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "WARNING: TiddlyWiki server not accessible initially. Waiting..."
    sleep 5
fi

# Create a dummy context tiddler so the user has some real-world flavor to refer to
cat > /home/ga/mywiki/tiddlers/Authentication_Service.tid << 'EOF'
title: Authentication Service
tags: Microservice Documentation

The Authentication Service (auth-service) is a core microservice that typically runs on port 8080 and is deployed via standard Docker/Kubernetes pipelines.
EOF
chown ga:ga /home/ga/mywiki/tiddlers/Authentication_Service.tid

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot for visual evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="