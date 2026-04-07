#!/bin/bash
echo "=== Setting up customize_wiki_settings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure tiddlers directory exists
mkdir -p "$TIDDLER_DIR"

# Record initial state of system tiddlers for anti-gaming comparison
for f in "$TIDDLER_DIR"/\$__*.tid; do
    if [ -f "$f" ]; then
        cp "$f" "/tmp/$(basename "$f").initial"
    fi
done

echo "=== Seeding wiki with UX Research content ==="

cat > "$TIDDLER_DIR/Project Overview.tid" << 'TIDDLER'
created: 20240115120000000
modified: 20240115120000000
tags: Project
title: Project Overview
type: text/vnd.tiddlywiki

! Meridian Health Portal Redesign

!! Client
Meridian Health Systems — a regional healthcare network with 12 hospitals and 45 outpatient clinics.

!! Project Scope
Redesign the patient-facing health portal to improve appointment scheduling workflows, lab results access, and secure messaging.

!! Timeline
* Discovery & Research: Jan 15 – Mar 1
* Synthesis & Ideation: Mar 4 – Apr 12
* Design & Prototyping: Apr 15 – Jun 7
TIDDLER

cat > "$TIDDLER_DIR/Research Plan.tid" << 'TIDDLER'
created: 20240116090000000
modified: 20240118140000000
tags: Research Project
title: Research Plan
type: text/vnd.tiddlywiki

! Research Plan — Meridian Health Portal

!! Methodology
!!! Phase 1: Contextual Inquiry
* 12 in-home observation sessions with current portal users
!!! Phase 2: Semi-Structured Interviews
* 20 interviews (60 min each)
!!! Phase 3: Competitive Analysis
* Evaluate MyChart, FollowMyHealth, Athena, Cerner
TIDDLER

cat > "$TIDDLER_DIR/Participant Screener.tid" << 'TIDDLER'
created: 20240117100000000
modified: 20240117153000000
tags: Research Recruitment
title: Participant Screener
type: text/vnd.tiddlywiki

! Participant Screener

# How often do you use the Meridian Health patient portal?
# Which of the following have you done on the portal?
# How would you rate your comfort with technology?
TIDDLER

# Set correct permissions
chown -R ga:ga "$TIDDLER_DIR"

# Ensure TiddlyWiki server is running and restart to pick up new tiddlers
echo "Restarting TiddlyWiki server to load seed tiddlers..."
pkill -f "tiddlywiki.*--listen" 2>/dev/null || true
sleep 3
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server
echo "Waiting for TiddlyWiki server..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Refresh Firefox to load fresh state
echo "Refreshing Firefox..."
sleep 3
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="