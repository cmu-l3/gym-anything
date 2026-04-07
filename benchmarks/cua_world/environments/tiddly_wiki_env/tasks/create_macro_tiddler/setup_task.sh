#!/bin/bash
set -e
echo "=== Setting up create_macro_tiddler task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

WIKI_DIR="/home/ga/mywiki"
TIDDLER_DIR="$WIKI_DIR/tiddlers"

# Clean target tiddlers if they exist to ensure clean state
rm -f "$TIDDLER_DIR/"*ProjectStatusMacro*.tid 2>/dev/null || true
rm -f "$TIDDLER_DIR/"*Active*Projects*.tid 2>/dev/null || true

# Seed context tiddlers for the scenario
cat > "$TIDDLER_DIR/Acme Corp.tid" << 'TIDEOF'
created: 20250102120000000
modified: 20250102120000000
tags: Clients
title: Acme Corp

! Acme Corp

|!Field |!Details |
|Industry |Manufacturing |
|Contact |Sarah Chen, VP of Digital |
|Email |sarah.chen@acmecorp.example.com |
|Phone |(555) 234-8901 |
|Location |Portland, OR |
|Relationship |Active since 2023 |

!! Notes

Acme Corp is a mid-size manufacturing company looking to modernize their web presence. They have been a reliable client with timely payments. Current project involves a full website redesign with e-commerce capabilities.
TIDEOF

cat > "$TIDDLER_DIR/TechStart Inc.tid" << 'TIDEOF'
created: 20250103090000000
modified: 20250103090000000
tags: Clients
title: TechStart Inc

! TechStart Inc

|!Field |!Details |
|Industry |SaaS / Technology |
|Contact |Marcus Rivera, CTO |
|Email |m.rivera@techstart.example.com |
|Phone |(555) 678-1234 |
|Location |Austin, TX |
|Relationship |New client, Q1 2025 |

!! Notes

TechStart is a seed-stage startup building a B2B SaaS product. They need a cross-platform mobile app MVP to demo to investors. Timeline is aggressive but budget is solid. First project together — building trust.
TIDEOF

cat > "$TIDDLER_DIR/RetailPlus.tid" << 'TIDEOF'
created: 20250104140000000
modified: 20250104140000000
tags: Clients
title: RetailPlus

! RetailPlus

|!Field |!Details |
|Industry |Retail / E-commerce |
|Contact |Diana Okoye, Head of IT |
|Email |d.okoye@retailplus.example.com |
|Phone |(555) 432-5678 |
|Location |Chicago, IL |
|Relationship |Active since 2024 |

!! Notes

RetailPlus operates 12 brick-and-mortar stores and wants to integrate their POS system with an online storefront. Project is currently on hold pending their internal infrastructure upgrade. Expected to resume in Q2 2025.
TIDEOF

cat > "$TIDDLER_DIR/Project Management.tid" << 'TIDEOF'
created: 20250101100000000
modified: 20250106100000000
tags: Navigation
title: Project Management

! Project Management Hub

This wiki serves as the central hub for tracking freelance web development projects.

!! Clients
* [[Acme Corp]]
* [[TechStart Inc]]
* [[RetailPlus]]

!! Workflow
# Initial consultation and proposal
# Contract signing
# Sprint planning
# Development and iteration
# QA and delivery
# Invoice and follow-up

!! TODO
* Create a standardized project status template for quick overview
* Build an active projects dashboard
TIDEOF

chown -R ga:ga "$TIDDLER_DIR"

# Restart TiddlyWiki server to pick up new tiddlers cleanly
echo "Restarting TiddlyWiki server..."
pkill -f "tiddlywiki.*--listen" 2>/dev/null || true
sleep 3
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server
for i in $(seq 1 30); do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Check if Firefox is running, if not start it
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Refresh and maximize Firefox
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5
sleep 3

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="