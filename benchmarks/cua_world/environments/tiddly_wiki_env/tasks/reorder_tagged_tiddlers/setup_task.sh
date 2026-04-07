#!/bin/bash
set -e
echo "=== Setting up reorder_tagged_tiddlers task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure TiddlyWiki server is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "Starting TiddlyWiki server..."
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    sleep 5
fi

# Wait for server
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Remove any pre-existing IncidentResponse tag tiddler (clean state)
rm -f "$TIDDLER_DIR/IncidentResponse.tid" 2>/dev/null || true

# Record initial tiddler count
count_user_tiddlers > /tmp/initial_tiddler_count.txt

# Create the six incident response procedure tiddlers
# Content based on NIST SP 800-61 Rev. 2 incident handling framework

cat > "$TIDDLER_DIR/Incident Detection and Alerting.tid" << 'TIDDLER_EOF'
created: 20240115120000000
modified: 20240115120000000
tags: IncidentResponse
title: Incident Detection and Alerting
type: text/vnd.tiddlywiki

! Incident Detection and Alerting
The first phase of incident response focuses on identifying potential security incidents through monitoring, alerting systems, and human observation. Early detection significantly reduces the impact and cost of security incidents.
TIDDLER_EOF

cat > "$TIDDLER_DIR/Initial Triage and Assessment.tid" << 'TIDDLER_EOF'
created: 20240115130000000
modified: 20240115130000000
tags: IncidentResponse
title: Initial Triage and Assessment
type: text/vnd.tiddlywiki

! Initial Triage and Assessment
Once a potential incident is detected, the response team must quickly assess the scope, severity, and potential impact to determine the appropriate level of response. Effective triage prevents both under-reaction and over-reaction.
TIDDLER_EOF

cat > "$TIDDLER_DIR/Communication and Escalation.tid" << 'TIDDLER_EOF'
created: 20240115140000000
modified: 20240115140000000
tags: IncidentResponse
title: Communication and Escalation
type: text/vnd.tiddlywiki

! Communication and Escalation
Timely and accurate communication during an incident is critical. The right people must be informed at the right time, using secure communication channels that have not been compromised.
TIDDLER_EOF

cat > "$TIDDLER_DIR/Containment and Mitigation.tid" << 'TIDDLER_EOF'
created: 20240115150000000
modified: 20240115150000000
tags: IncidentResponse
title: Containment and Mitigation
type: text/vnd.tiddlywiki

! Containment and Mitigation
Containment aims to limit the damage from the incident and prevent further spread. This phase requires balancing the urgency of stopping the attack against the need to preserve evidence for later forensic analysis.
TIDDLER_EOF

cat > "$TIDDLER_DIR/Recovery and Restoration.tid" << 'TIDDLER_EOF'
created: 20240115160000000
modified: 20240115160000000
tags: IncidentResponse
title: Recovery and Restoration
type: text/vnd.tiddlywiki

! Recovery and Restoration
The recovery phase focuses on restoring affected systems to normal operation while ensuring the threat has been fully eradicated. Premature return to production without thorough validation is a leading cause of incident recurrence.
TIDDLER_EOF

cat > "$TIDDLER_DIR/Post-Incident Review.tid" << 'TIDDLER_EOF'
created: 20240115170000000
modified: 20240115170000000
tags: IncidentResponse
title: Post-Incident Review
type: text/vnd.tiddlywiki

! Post-Incident Review
The post-incident review (lessons learned) is the most valuable phase of incident response. Every incident should have a review to improve future response capabilities and document timeline reconstructions.
TIDDLER_EOF

# Set permissions
chown ga:ga "$TIDDLER_DIR"/*.tid

# Restart TiddlyWiki to pick up new tiddlers
pkill -f "tiddlywiki mywiki --listen" 2>/dev/null || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server restart
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server restarted"
        break
    fi
    sleep 1
done

# Ensure Firefox is running and showing TiddlyWiki
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|tiddly"; then
    echo "Launching Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Maximize and focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Refresh Firefox to show new tiddlers
DISPLAY=:1 xdotool key F5
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="