#!/bin/bash
echo "=== Setting up configure_math_and_code_plugins task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time

# 1. Reset tiddlywiki.info to default (no math/code plugins)
cat > /tmp/tiddlywiki.info << 'EOF'
{
    "description": "Basic client-server edition",
    "plugins": [
        "tiddlywiki/tiddlyweb",
        "tiddlywiki/filesystem"
    ],
    "themes": [
        "tiddlywiki/vanilla",
        "tiddlywiki/snowwhite"
    ]
}
EOF
cp /tmp/tiddlywiki.info /home/ga/mywiki/tiddlywiki.info
chown ga:ga /home/ga/mywiki/tiddlywiki.info

# 2. Restart server to ensure clean state
echo "Restarting TiddlyWiki server..."
pkill -f tiddlywiki
sleep 2
su - ga -c "cd /home/ga/mywiki && nohup tiddlywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
sleep 3

# Record the initial process ID to verify agent restarts it
pgrep -f "tiddlywiki" | head -1 > /tmp/initial_tw_pid
echo "Initial TiddlyWiki PID: $(cat /tmp/initial_tw_pid)"

# 3. Clean up any existing Softmax tiddler
rm -f "/home/ga/mywiki/tiddlers/Softmax Function.tid" 2>/dev/null || true

# 4. Ensure Firefox is open to the correct URL and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080/ &"
    sleep 5
fi

DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="