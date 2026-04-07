#!/bin/bash
echo "=== Setting up delete_deprecated_tiddlers task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop TiddlyWiki
pkill -f "tiddlywiki" 2>/dev/null || true
sleep 2

# Clear existing user tiddlers
find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -delete 2>/dev/null || true

echo "Creating lab notebook tiddlers..."

# Create deprecated tiddlers
cat > "$TIDDLER_DIR/PCR Protocol v1.tid" << 'EOF'
title: PCR Protocol v1
tags: Deprecated Protocol

! PCR Protocol Version 1 (SUPERSEDED)
Note: This protocol uses standard Taq. See [[PCR Protocol v3]] for the updated version.
EOF

cat > "$TIDDLER_DIR/Supplier List 2022.tid" << 'EOF'
title: Supplier List 2022
tags: Deprecated Reference

! Supplier List 2022 (OUTDATED)
This list is no longer maintained. See [[Current Supplier List]] for up-to-date information.
EOF

cat > "$TIDDLER_DIR/Old Lab Safety Rules.tid" << 'EOF'
title: Old Lab Safety Rules
tags: Deprecated Safety

! Lab Safety Rules (SUPERSEDED 2021)
These rules have been replaced by [[Lab Safety Guidelines 2024]]. Do not follow this version.
EOF

cat > "$TIDDLER_DIR/Western Blot Protocol v2.tid" << 'EOF'
title: Western Blot Protocol v2
tags: Deprecated Protocol

! Western Blot Protocol v2 (SUPERSEDED)
This protocol has been replaced by [[Western Blot Protocol v4]].
EOF

cat > "$TIDDLER_DIR/Budget Proposal Q1 2023.tid" << 'EOF'
title: Budget Proposal Q1 2023
tags: Deprecated Administrative

! Budget Proposal - Q1 2023 (EXPIRED)
This budget proposal is no longer active. Funding period has ended.
EOF

# Create preserved tiddlers
cat > "$TIDDLER_DIR/PCR Protocol v3.tid" << 'EOF'
title: PCR Protocol v3
tags: Active Protocol

! PCR Protocol Version 3 (CURRENT)
High-fidelity PCR protocol using Q5 polymerase for cloning and sequencing applications.
EOF

cat > "$TIDDLER_DIR/Western Blot Protocol v4.tid" << 'EOF'
title: Western Blot Protocol v4
tags: Active Protocol

! Western Blot Protocol v4 (CURRENT)
Key Changes from v2: Switched from wet transfer to semi-dry transfer.
EOF

cat > "$TIDDLER_DIR/Lab Meeting Notes 2024-01-15.tid" << 'EOF'
title: Lab Meeting Notes 2024-01-15
tags: MeetingNotes

! Lab Meeting - January 15, 2024
Attendees: Dr. Martinez, Sarah K., James L.
EOF

cat > "$TIDDLER_DIR/Current Supplier List.tid" << 'EOF'
title: Current Supplier List
tags: Active Reference

! Current Supplier List (Updated 2024)
Primary Suppliers: Fisher Scientific, MilliporeSigma, VWR.
EOF

cat > "$TIDDLER_DIR/Lab Safety Guidelines 2024.tid" << 'EOF'
title: Lab Safety Guidelines 2024
tags: Active Safety

! Lab Safety Guidelines 2024 (CURRENT)
These guidelines supersede all previous safety documents including [[Old Lab Safety Rules]].
EOF

cat > "$TIDDLER_DIR/Equipment Inventory.tid" << 'EOF'
title: Equipment Inventory
tags: Active Reference

! Lab Equipment Inventory
Major Equipment: Thermocyclers, Centrifuges, Freezers.
EOF

cat > "$TIDDLER_DIR/Research Project Alpha.tid" << 'EOF'
title: Research Project Alpha
tags: Active Project

! Research Project Alpha
Role of SIRT3 in Mitochondrial Stress Response. PI: Dr. Elena Martinez.
EOF

cat > "$TIDDLER_DIR/Graduate Student Onboarding.tid" << 'EOF'
title: Graduate Student Onboarding
tags: Active Administrative

! Graduate Student Onboarding Checklist
Before First Day: Building access card, Lab key, Computer account.
EOF

chown -R ga:ga "$TIDDLER_DIR"

# Record initial state: list all tiddler filenames
find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -exec basename {} .tid \; | sort > /tmp/initial_tiddlers.txt
echo "Initial tiddler count: $(wc -l < /tmp/initial_tiddlers.txt)"

# Start TiddlyWiki server
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for TiddlyWiki server to start
echo "Waiting for TiddlyWiki server..."
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running on port 8080"
        break
    fi
    sleep 1
done

# Ensure Firefox is running and focused
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|tiddly"; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Refresh Firefox to show current wiki state
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5
sleep 3

# Maximize and focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="