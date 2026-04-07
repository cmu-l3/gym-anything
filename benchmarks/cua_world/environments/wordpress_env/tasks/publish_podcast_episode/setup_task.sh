#!/bin/bash
echo "=== Setting up publish_podcast_episode task ==="

source /workspace/scripts/task_utils.sh

# 1. Create Podcast directory and files on Desktop
mkdir -p /home/ga/Desktop/Podcast

# Create transcript.txt
cat << 'EOF' > /home/ga/Desktop/Podcast/transcript.txt
[00:00:00] Host: Welcome to Tech Insights. In our inaugural episode, we discuss the evolution of cloud infrastructure.
[00:00:10] Guest: Startups today don't want to manage Kubernetes clusters. They want serverless scalability from day one.
[00:00:25] Host: Exactly. The abstraction layers are getting thicker, and that's a good thing for product velocity.
EOF

# Create a valid (but tiny/silent) MP3 file using base64
python3 -c '
import base64
mp3_b64 = "SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA//OEwAAAAANIAAAAAExBTUUzLjEwMKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
with open("/home/ga/Desktop/Podcast/tech_insights_raw_ep1.mp3", "wb") as f:
    f.write(base64.b64decode(mp3_b64))
'
chown -R ga:ga /home/ga/Desktop/Podcast
chown -R ga:ga /home/ga/Desktop/Podcast/*

# Record baseline task start
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="