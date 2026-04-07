#!/bin/bash
set -e
echo "=== Setting up create_toc_hierarchy task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

# Ensure tiddlers directory exists
mkdir -p "$TIDDLER_DIR"
chown -R ga:ga "$WIKI_DIR"

# Generate the 12 seed tiddlers to guarantee they are present and untagged
echo "Generating seed tiddlers..."

cat << 'EOF' > /tmp/generate_seed_tiddlers.js
const fs = require('fs');
const path = require('path');

const tiddlers = [
  { title: "Database Schema Design", text: "! Database Schema Design\nProjectAlpha uses PostgreSQL 15 as its primary data store." },
  { title: "Microservices Overview", text: "! Microservices Overview\nProjectAlpha is decomposed into five core services communicating over gRPC." },
  { title: "Authentication Flow", text: "! Authentication Flow\nProjectAlpha implements OAuth 2.0 with PKCE for browser clients." },
  { title: "REST API Endpoints", text: "! REST API Endpoints\nThe public REST API is served at `https://api.projectalpha.io/v1/`." },
  { title: "GraphQL Queries", text: "! GraphQL Queries\nProjectAlpha exposes a GraphQL endpoint for clients that need flexible data fetching." },
  { title: "Error Codes Reference", text: "! Error Codes Reference\nProjectAlpha uses structured error codes across all API surfaces." },
  { title: "WebSocket Events", text: "! WebSocket Events\nProjectAlpha uses WebSocket connections for real-time updates." },
  { title: "Installation Guide", text: "! Installation Guide\nThis guide walks through setting up ProjectAlpha for local development." },
  { title: "Configuration Options", text: "! Configuration Options\nProjectAlpha services are configured via environment variables." },
  { title: "Development Environment Setup", text: "! Development Environment Setup\nThis guide covers IDE configuration and developer tooling." },
  { title: "Deployment Checklist", text: "! Deployment Checklist\nFollow this checklist for every production deployment." },
  { title: "Troubleshooting Common Issues", text: "! Troubleshooting Common Issues\nThis page documents frequently encountered issues." }
];

const tiddlerDir = "/home/ga/mywiki/tiddlers";

tiddlers.forEach(t => {
  let filename = t.title.replace(/[\/\\:*?"<>|]/g, "_").replace(/\s+/g, " ");
  let filepath = path.join(tiddlerDir, filename + ".tid");
  
  // Create with no tags
  let content = `title: ${t.title}\ntype: text/vnd.tiddlywiki\n\n${t.text}\n`;
  fs.writeFileSync(filepath, content, "utf8");
});
EOF

su - ga -c "node /tmp/generate_seed_tiddlers.js"

# Ensure permissions are correct
chown -R ga:ga "$TIDDLER_DIR"

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count.txt
echo "Seed tiddlers generated. Total tiddlers: $INITIAL_COUNT"

# Ensure TiddlyWiki server is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "Restarting TiddlyWiki server..."
    pkill -f "tiddlywiki.*listen" 2>/dev/null || true
    sleep 2
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    sleep 5
fi

# Ensure Firefox is open to TiddlyWiki
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|tiddly"; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Maximize and focus Firefox
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        echo "Firefox maximized and focused"
        break
    fi
    sleep 1
done

# Refresh the page to ensure latest tiddlers are loaded
sleep 2
DISPLAY=:1 xdotool key F5
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="