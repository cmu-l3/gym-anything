#!/bin/bash
echo "=== Setting up build_tiddler_generator_form task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Seed the wiki with some realistic patient data so the agent sees the expected context
echo "Seeding dummy patient records..."

cat << 'EOF' > "$TIDDLER_DIR/Maria Garcia.tid"
tags: Patient
title: Maria Garcia
dob: 1975-08-22
physician: Dr. Chen

!! Intake Notes
* Patient complains of mild hypertension. Follow-up scheduled.
EOF

cat << 'EOF' > "$TIDDLER_DIR/Robert Johnson.tid"
tags: Patient
title: Robert Johnson
dob: 1960-11-05
physician: Dr. Smith

!! Intake Notes
* Follow-up for Type 2 Diabetes. Blood sugar levels stable.
EOF

cat << 'EOF' > "$TIDDLER_DIR/James Wilson.tid"
tags: Patient
title: James Wilson
dob: 1992-03-15
physician: Dr. Chen

!! Intake Notes
* Annual physical. No concerns.
EOF

chown ga:ga "$TIDDLER_DIR/"*.tid

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not responding!"
fi

# Ensure Firefox is focused and ready
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot showing the pre-existing patients
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="