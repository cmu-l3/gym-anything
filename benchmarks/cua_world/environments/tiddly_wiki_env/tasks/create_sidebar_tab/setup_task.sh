#!/bin/bash
echo "=== Setting up create_sidebar_tab task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create seed data for ProjectAlpha
cat > /tmp/seed_projects.json << 'EOF'
[
  {"title": "Sprint Planning Meeting - Jan 15", "tags": "ProjectAlpha Meetings", "text": "Attendees: Alice, Bob.\nGoals: Finalize API."},
  {"title": "Architecture Decision Record 001", "tags": "ProjectAlpha Architecture", "text": "Decision: Use microservices."},
  {"title": "Client Requirements Document", "tags": "ProjectAlpha Requirements", "text": "Must support 10k concurrent users."},
  {"title": "API Integration Notes", "tags": "ProjectAlpha Technical", "text": "Bloomberg API details."},
  {"title": "Budget Forecast Q1", "tags": "ProjectAlpha Finance", "text": "Total budget: $500k."},
  {"title": "Database Schema Notes", "tags": "ProjectAlpha Technical", "text": "Users table, Projects table."},
  {"title": "Compliance Framework Overview", "tags": "ProjectAlpha Compliance", "text": "FINRA regulations apply."},
  {"title": "Weekly Status Report - Week 3", "tags": "Reports StatusUpdate", "text": "Everything is on track."},
  {"title": "Team Contact Directory", "tags": "Reference HR", "text": "Alice: 555-0101."},
  {"title": "Onboarding Checklist", "tags": "HR Process", "text": "1. Setup email\n2. Get badge."}
]
EOF

# Use node to parse and seed the tiddlers
su - ga -c 'node -e "
const fs = require(\"fs\");
const path = require(\"path\");
try {
    const tiddlers = JSON.parse(fs.readFileSync(\"/tmp/seed_projects.json\", \"utf8\"));
    const tiddlerDir = \"/home/ga/mywiki/tiddlers\";
    if (!fs.existsSync(tiddlerDir)) fs.mkdirSync(tiddlerDir, { recursive: true });
    tiddlers.forEach(t => {
        let filename = t.title.replace(/[\/\\\\:*?\"<>|]/g, \"_\").replace(/\\s+/g, \" \");
        let filepath = path.join(tiddlerDir, filename + \".tid\");
        let content = \"title: \" + t.title + \"\\ntags: \" + t.tags + \"\\n\\n\" + t.text;
        fs.writeFileSync(filepath, content, \"utf8\");
    });
    console.log(\"Seeded \" + tiddlers.length + \" project tiddlers\");
} catch(e) {
    console.error(\"Error seeding:\", e);
}
"'

# Remove any pre-existing ProjectDashboard tiddler
rm -f "/home/ga/mywiki/tiddlers/\$__custom_ProjectDashboard.tid" 2>/dev/null || true

# Verify TiddlyWiki server is running, if not start it
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "Starting TiddlyWiki server..."
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    sleep 5
fi

# Ensure Firefox is open
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Refresh Firefox to pick up current seeded state
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate --sync key F5 2>/dev/null || true
sleep 3

# Maximize and focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="