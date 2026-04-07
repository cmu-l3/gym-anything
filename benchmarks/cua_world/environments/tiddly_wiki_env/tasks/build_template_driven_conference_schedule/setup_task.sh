#!/bin/bash
echo "=== Setting up Conference Schedule task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create FOSDEM 2024 sample data
echo "Generating real conference session data..."
cat > /tmp/fosdem_sessions.json << 'EOF'
[
  {"title": "Matrix 2.0", "time": "10:00", "room": "K.1.105", "speaker": "Matthew Hodgson", "track": "Real Time", "text": "Matrix 2.0 introduces invisible, blazing fast, and scalable decentralized communication. We will explore the new Matrix Rust SDK and sliding sync."},
  {"title": "The State of Wayland", "time": "11:00", "room": "Janson", "speaker": "Simon Ser", "track": "Graphics", "text": "An update on the Wayland ecosystem. We will cover recent protocol extensions, tearing updates, HDR support progress, and broader adoption across desktop environments."},
  {"title": "OpenStreetMap in 2024", "time": "13:00", "room": "UD2.120", "speaker": "Sarah Hoffmann", "track": "Geospatial", "text": "The future of OSM. Examining the vector tile rollout, the new data model discussions, and how the community is scaling to map the entire globe."},
  {"title": "PostgreSQL 16 Features", "time": "14:30", "room": "H.1301", "speaker": "Magnus Hagander", "track": "Databases", "text": "Deep dive into PG16. Learn about the new logical replication improvements, I/O monitoring enhancements, and query planner optimizations."},
  {"title": "Rust in the Linux Kernel", "time": "09:00", "room": "Janson", "speaker": "Miguel Ojeda", "track": "Kernel", "text": "Status of Rust in Linux. A review of the subsystems adopting Rust, the GCC frontend progress, and upcoming abstractions."},
  {"title": "Home Assistant Year of the Voice", "time": "12:00", "room": "H.2215", "speaker": "Paulus Schoutsen", "track": "IoT", "text": "Local voice control for the smart home. How Home Assistant is building out Wake Word and local natural language processing capabilities."},
  {"title": "KDE Plasma 6", "time": "15:00", "room": "K.1.105", "speaker": "Nate Graham", "track": "Desktop", "text": "What is new in the KDE Plasma 6 mega-release. Transitioning to Qt 6, Wayland by default, and a refreshed user interface."},
  {"title": "Systemd Updates", "time": "16:00", "room": "Janson", "speaker": "Lennart Poettering", "track": "Core", "text": "Systemd in 2024. Covering soft-reboot features, measured boot integration, and modernizing the Linux boot process."}
]
EOF

# Use node to create the .tid files with custom fields
su - ga -c 'node -e "
const fs = require(\"fs\");
const sessions = JSON.parse(fs.readFileSync(\"/tmp/fosdem_sessions.json\"));
const dir = \"/home/ga/mywiki/tiddlers/\";
sessions.forEach(s => {
  const content = \`title: \${s.title}\ntime: \${s.time}\nroom: \${s.room}\nspeaker: \${s.speaker}\ntrack: \${s.track}\ntags: Session\n\n\${s.text}\`;
  fs.writeFileSync(dir + s.title + \".tid\", content);
});
"'

# Restart TiddlyWiki to ensure all new files are loaded correctly
echo "Restarting TiddlyWiki server..."
pkill -f tiddlywiki 2>/dev/null || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for TiddlyWiki to come back up
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is back online"
        break
    fi
    sleep 1
done

# Ensure Firefox is open and refresh it
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Focus, Maximize and Refresh Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key F5
    sleep 3
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="