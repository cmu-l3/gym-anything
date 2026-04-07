#!/bin/bash
echo "=== Setting up build_interactive_transit_explorer task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_time

# Create seed tiddlers for CTA stations
echo "Generating CTA station seed data..."

cat << 'EOF' > /tmp/generate_stations.js
const fs = require('fs');
const path = require('path');
const tiddlerDir = '/home/ga/mywiki/tiddlers';

if (!fs.existsSync(tiddlerDir)) {
    fs.mkdirSync(tiddlerDir, { recursive: true });
}

const stations = [
  {"title": "Howard", "lines": "Red Purple Yellow", "ada": "yes"},
  {"title": "Fullerton", "lines": "Red Brown Purple", "ada": "yes"},
  {"title": "Clark-Lake", "lines": "Blue Green Brown Orange Pink Purple", "ada": "yes"},
  {"title": "O'Hare", "lines": "Blue", "ada": "yes"},
  {"title": "Logan Square", "lines": "Blue", "ada": "yes"},
  {"title": "Belmont", "lines": "Red Brown Purple", "ada": "yes"},
  {"title": "Roosevelt", "lines": "Red Green Orange", "ada": "yes"},
  {"title": "Jackson", "lines": "Red Blue", "ada": "yes"},
  {"title": "Washington-Wabash", "lines": "Green Brown Orange Pink Purple", "ada": "yes"},
  {"title": "Ashland", "lines": "Green Pink", "ada": "yes"},
  {"title": "Damen", "lines": "Blue", "ada": "no"},
  {"title": "Western", "lines": "Blue", "ada": "yes"},
  {"title": "Garfield", "lines": "Green", "ada": "yes"},
  {"title": "Midway", "lines": "Orange", "ada": "yes"},
  {"title": "Kimball", "lines": "Brown", "ada": "yes"}
];

stations.forEach(s => {
  const content = `title: ${s.title}\ntags: Station\nlines: ${s.lines}\nada-accessible: ${s.ada}\n\n`;
  const filename = path.join(tiddlerDir, s.title.replace(/[^a-zA-Z0-9 ]/g, '_') + '.tid');
  fs.writeFileSync(filename, content);
});
EOF

su - ga -c "node /tmp/generate_stations.js"

# Wait a moment for TiddlyWiki's filesystem watcher to pick up the new files
sleep 3

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot showing loaded state
take_screenshot /tmp/transit_initial.png

echo "=== Task setup complete ==="