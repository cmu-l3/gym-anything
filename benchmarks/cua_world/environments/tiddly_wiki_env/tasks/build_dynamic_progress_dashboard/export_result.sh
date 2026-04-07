#!/bin/bash
echo "=== Exporting build_dynamic_progress_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/dashboard_final.png

# 1. Render the initial state of the dashboard to HTML via TiddlyWiki CLI
echo "Rendering initial dashboard HTML..."
su - ga -c "cd /home/ga/mywiki && tiddlywiki --render 'Level Completion Tracker' 'tracker_initial.html' 'text/plain' '\$:/core/templates/tiddler-body'" 2>/dev/null || true

# 2. Mutate task statuses to test for dynamic anti-gaming calculation
echo "Mutating underlying task states..."
sed -i 's/status: in-progress/status: done/g' "/home/ga/mywiki/tiddlers/Rig elevator platform.tid"
sed -i 's/status: todo/status: done/g' "/home/ga/mywiki/tiddlers/Neon signs.tid"

# Sleep briefly to ensure Node watcher (if any) could settle, though CLI doesn't strictly need it
sleep 2

# 3. Re-render the dashboard to capture updated dynamic math
echo "Rendering mutated dashboard HTML..."
su - ga -c "cd /home/ga/mywiki && tiddlywiki --render 'Level Completion Tracker' 'tracker_mutated.html' 'text/plain' '\$:/core/templates/tiddler-body'" 2>/dev/null || true

# 4. Use Python to safely package all the results into a JSON file
python3 << 'EOF'
import json
import os

def read_file(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception:
        return ""

# Check tiddler fields
stylesheet_content = read_file("/home/ga/mywiki/tiddlers/ProgressBarStyles.tid")
dashboard_content = read_file("/home/ga/mywiki/tiddlers/Level Completion Tracker.tid")

# Determine tags (primitive check, robust check in verifier)
is_stylesheet = "tags: $:/tags/Stylesheet" in stylesheet_content
is_dashboard = "tags: Dashboard" in dashboard_content or "tags: [[Dashboard]]" in dashboard_content

result = {
    "stylesheet_exists": os.path.exists("/home/ga/mywiki/tiddlers/ProgressBarStyles.tid"),
    "dashboard_exists": os.path.exists("/home/ga/mywiki/tiddlers/Level Completion Tracker.tid"),
    "is_tagged_stylesheet": is_stylesheet,
    "is_tagged_dashboard": is_dashboard,
    "stylesheet_content": stylesheet_content,
    "dashboard_content": dashboard_content,
    "initial_html": read_file("/home/ga/mywiki/output/tracker_initial.html"),
    "mutated_html": read_file("/home/ga/mywiki/output/tracker_mutated.html"),
    "timestamp": os.popen("date -Iseconds").read().strip()
}

with open("/tmp/dashboard_result.json", "w", encoding='utf-8') as f:
    json.dump(result, f, indent=2)
EOF

echo "Result safely exported to /tmp/dashboard_result.json"
echo "=== Export complete ==="