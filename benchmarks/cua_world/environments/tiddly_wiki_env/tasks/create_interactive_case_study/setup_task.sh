#!/bin/bash
echo "=== Setting up create_interactive_case_study task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Wait for TiddlyWiki server to be ready
echo "Waiting for TiddlyWiki server..."
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running on port 8080"
        break
    fi
    sleep 1
done

# 3. Seed the wiki with medical context tiddlers
TIDDLER_DIR="/home/ga/mywiki/tiddlers"
mkdir -p "$TIDDLER_DIR"

cat > "$TIDDLER_DIR/Medical Cases Index.tid" << 'EOF'
title: Medical Cases Index
tags: TableOfContents
type: text/vnd.tiddlywiki

Welcome to the interactive case library. Select a case below to practice your clinical reasoning.

<<list-links "[tag[CaseStudy]]">>
EOF

cat > "$TIDDLER_DIR/Pulmonology.tid" << 'EOF'
title: Pulmonology
tags: Specialty
type: text/vnd.tiddlywiki

Pulmonology reference notes and case studies.
EOF

cat > "$TIDDLER_DIR/Teaching Resources.tid" << 'EOF'
title: Teaching Resources
tags: TableOfContents
type: text/vnd.tiddlywiki

Tools and methods for medical education, including the Socratic method and progressive reveal cases.
EOF

cat > "$TIDDLER_DIR/Case Study_ Diabetic Ketoacidosis.tid" << 'EOF'
title: Case Study: Diabetic Ketoacidosis
tags: CaseStudy Endocrinology
type: text/vnd.tiddlywiki

A simple, non-interactive case study about a 22-year-old female presenting with DKA.
EOF

cat > "$TIDDLER_DIR/Clinical Reasoning Framework.tid" << 'EOF'
title: Clinical Reasoning Framework
tags: Teaching
type: text/vnd.tiddlywiki

The stepwise approach to clinical cases:
1. History of Present Illness
2. Physical Examination
3. Investigations
4. Diagnosis and Management
EOF

chown -R ga:ga "$TIDDLER_DIR"

# Wait a moment for TiddlyWiki to ingest the seed files
sleep 3

# 4. Ensure Firefox is running and focused
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# 5. Dismiss any open tiddlers by navigating to home
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="