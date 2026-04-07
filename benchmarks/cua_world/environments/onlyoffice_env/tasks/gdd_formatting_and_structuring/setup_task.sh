#!/bin/bash
set -euo pipefail

echo "=== Setting up GDD Formatting Task ==="

# Source ONLYOFFICE utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Clean up any existing instances or files
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
rm -f /tmp/task_start_time.txt /tmp/task_result.json
rm -f /home/ga/Documents/TextDocuments/Eldoria_GDD.docx
sleep 1

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure target directory exists
mkdir -p /home/ga/Documents/TextDocuments

# Create the raw text file with realistic, messy GDD notes
RAW_FILE="/home/ga/Documents/TextDocuments/raw_gdd.txt"
cat > "$RAW_FILE" << 'EOF'
Eldoria: Awakening - Game Design Document

1. Executive Summary
Eldoria: Awakening is a dark fantasy action-RPG focusing on high-mobility combat and deep class customization. Players explore the ruined kingdom of Eldoria to seal the Abyssal Rifts.

2. Core Gameplay Mechanics
The core loop consists of exploration, resource gathering, and instance-based dungeon crawling. 

2.1 Movement and Traversal
Traversal is fluid and stamina-based. Press Spacebar to jump, Left Shift to sprint, and F to interact.

2.2 Combat System
Combat requires precise timing. Combat uses Left Mouse Button for light attacks, Right Mouse Button for heavy attacks, and Q for the class special.

3. Character Classes
The game features four distinct archetypes. 

Class, Base HP, Base Mana, Primary Weapon, Special Ability, Difficulty
Spellblade, 120, 200, Rapier, Arcane Dash, Hard
Ironclad, 250, 50, Warhammer, Seismic Slam, Easy
Shadow Weaver, 90, 150, Dual Daggers, Smoke Cloak, Medium
Ranger, 110, 100, Longbow, Volley, Medium

4. Level Design
Levels are semi-open hubs connected by linear, heavily guarded pathways.

4.1 The Sunken Keep (Tutorial)
A flooded fortress that introduces the player to swimming and basic combat.

4.2 The Ashen Peaks
A mid-game vertical level requiring extensive use of the grappling hook.

5. Monetization Strategy
The game will be a premium release with cosmetic-only DLC packs available post-launch. No pay-to-win elements will be included.
EOF

chown ga:ga "$RAW_FILE"

# Launch ONLYOFFICE with the raw text file
echo "Starting ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$RAW_FILE' > /dev/null 2>&1 &"

# Wait for ONLYOFFICE window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "onlyoffice"; then
        echo "ONLYOFFICE window detected."
        break
    fi
    sleep 1
done

# Focus and maximize the window
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Give UI time to settle
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="