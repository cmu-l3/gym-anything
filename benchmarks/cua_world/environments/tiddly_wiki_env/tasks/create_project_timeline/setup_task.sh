#!/bin/bash
set -e
echo "=== Setting up create_project_timeline task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure TiddlyWiki server is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "Starting TiddlyWiki server..."
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
fi

# Wait for server
for i in $(seq 1 30); do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Create context tiddlers
cat > "$TIDDLER_DIR/Project Overview.tid" << 'TIDEOF'
created: 20240915120000000
modified: 20250110150000000
tags: ProjectInfo
title: Project Overview

! Community Health Outcomes Longitudinal Study

''Grant:'' NIH R01-HL-163892
''PI:'' Dr. Maria Santos
''Institution:'' University of Michigan School of Public Health
''Period:'' September 2024 – August 2027
''Funding:'' $2.4M (total costs)

This three-year study examines the long-term cardiovascular health outcomes in underserved communities across southeastern Michigan. The study employs a mixed-methods approach combining clinical measurements, validated survey instruments, and community health worker interventions.
TIDEOF

cat > "$TIDDLER_DIR/Team Members.tid" << 'TIDEOF'
created: 20240915130000000
modified: 20241201100000000
tags: ProjectInfo
title: Team Members

! Research Team
* Dr. Maria Santos, PhD, MPH
* Dr. James Chen, PhD
* Dr. Fatima Al-Rashid, MD
* Sarah Johnson, MPH
TIDEOF

chown ga:ga "$TIDDLER_DIR/Project Overview.tid" "$TIDDLER_DIR/Team Members.tid"

# Remove any pre-existing milestone or timeline tiddlers
for title in "IRB Protocol Submission" "Equipment Procurement" "Participant Recruitment Phase 1" "Interim Data Analysis" "Year 1 Progress Report to NIH" "Project Timeline"; do
    sanitized=$(echo "$title" | sed 's/[\/\\:*?"<>|]/_/g')
    rm -f "$TIDDLER_DIR/${sanitized}.tid" 2>/dev/null || true
done

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count.txt
echo "Initial user tiddler count: $INITIAL_COUNT"

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Refresh Firefox to load new tiddlers
sleep 1
DISPLAY=:1 xdotool key F5
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="