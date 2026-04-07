#!/bin/bash
echo "=== Setting up create_crm_dashboard_aggregations task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time

# Seed the wiki with 12 client tiddlers
echo "Creating client data..."
TIDDLER_DIR="/home/ga/mywiki/tiddlers"
mkdir -p "$TIDDLER_DIR"

create_client() {
    local name="$1"
    local status="$2"
    local revenue="$3"
    local industry="$4"
    
    cat << EOF > "$TIDDLER_DIR/${name}.tid"
title: $name
tags: Client
client_name: $name
status: $status
revenue: $revenue
industry: $industry

Detailed notes and contact information for $name.
EOF
}

# 6 Active Clients (Original Active Sum = 900,000, Max = 250,000)
create_client "TechCorp" "Active" "100000" "Software"
create_client "Alpha Inc" "Active" "150000" "Manufacturing"
create_client "Beta LLC" "Active" "200000" "Logistics"
create_client "Zeta Analytics" "Active" "120000" "Finance"
create_client "Iota Labs" "Active" "80000" "Research"
create_client "Lambda Corp" "Active" "250000" "Software"

# 4 Prospect Clients (Original Prospect Sum = 900,000)
create_client "Gamma Co" "Prospect" "300000" "Retail"
create_client "Delta Org" "Prospect" "50000" "Consulting"
create_client "Eta Systems" "Prospect" "400000" "Health"
create_client "Kappa Partners" "Prospect" "150000" "Finance"

# 2 Churned Clients
create_client "Epsilon Net" "Churned" "75000" "Software"
create_client "Theta Group" "Churned" "300000" "Manufacturing"

chown -R ga:ga "$TIDDLER_DIR"

# Restart TiddlyWiki to ensure all seeded tiddlers are loaded
echo "Restarting TiddlyWiki to index seeded content..."
pkill -f tiddlywiki 2>/dev/null || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server to be up
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Ensure Firefox is open and refresh it
echo "Configuring Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080/ &"
    sleep 5
fi

# Focus Firefox, maximize, and refresh page to show new clients
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key ctrl+r
sleep 3

take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="