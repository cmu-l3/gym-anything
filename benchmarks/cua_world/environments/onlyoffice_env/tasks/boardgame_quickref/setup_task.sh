#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Board Game Quick Reference Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create paths
DOC_PATH="$WORKSPACE_DIR/GameReference.docx"
RULEBOOK_PATH="$WORKSPACE_DIR/game_rulebook_excerpt.txt"

# Create the rulebook excerpt for context
cat > "$RULEBOOK_PATH" << 'EOF'
=== STARFALL COLONIES - RULEBOOK EXCERPT ===

A strategic resource management game for 2-4 players where you build colonies on distant planets.

OBJECTIVE: Be the first player to establish 5 successful colonies and collect 20 Victory Points.

TURN STRUCTURE:
Each player's turn consists of four phases that must be completed in order:
1. Resource Phase - Collect resources from your existing colonies
2. Action Phase - Perform up to 2 actions from the available action list
3. Event Phase - Draw and resolve one event card
4. Cleanup Phase - Discard excess cards and pass turn marker

AVAILABLE ACTIONS:
During the Action Phase, players may choose from these actions (max 2 per turn):

- Build Colony: Spend 3 Metal + 2 Energy to place a new colony marker on an unclaimed planet space
- Upgrade Colony: Spend 2 Metal + 1 Crystal to upgrade an existing colony (produces +1 resource)
- Research Technology: Spend 2 Energy + 1 Crystal to draw a technology card
- Trade Resources: Exchange resources with the supply at a 3:1 ratio for any resource type
- Recruit Colonist: Spend 1 Food to gain a colonist token (required for some advanced actions)
- Explore: Spend 1 Energy to reveal a new planet card from the exploration deck

PHASE DETAILS:

Resource Phase: Each colony you control produces resources. Check the planet type:
  - Industrial planets produce 2 Metal
  - Energy planets produce 2 Energy
  - Crystal planets produce 1 Crystal
  - Agricultural planets produce 2 Food
  Upgraded colonies produce +1 additional resource.

Action Phase: Choose and perform up to 2 actions. You may perform the same action twice if desired. Some technology cards may grant bonus actions.

Event Phase: Draw the top card from the Event deck. Events may be positive (gain resources, bonus points) or negative (lose resources, colony damage). Follow the card instructions and discard.

Cleanup Phase: Check hand limit (7 cards maximum). Discard excess cards. Return any temporary tokens to the supply. Pass the First Player marker clockwise to the next player.

IMPORTANT RULES:
- You cannot build on a planet already occupied by another player
- Resource storage is unlimited
- Technology cards are kept secret until played
- Event cards are revealed to all players and discarded after resolution
- The game ends immediately when a player places their 5th colony AND has 20+ Victory Points
- If multiple players achieve this in the same round, the player with the most Victory Points wins

RESOURCES:
- Metal (grey cube): Used for building and upgrading
- Energy (yellow cube): Used for actions and research
- Crystal (blue cube): Rare resource for advanced actions
- Food (green cube): Used for recruiting colonists

VICTORY POINTS:
- Each colony: 3 points
- Each upgraded colony: +2 points (5 total)
- Each technology card: 1-3 points (varies by card)
- Some event cards award bonus points

SETUP:
Place the game board in center. Each player takes a player board, 3 Metal, 2 Energy, 1 Food starting resources, and 2 random technology cards. Shuffle planet deck and event deck. Reveal 3 planets to the exploration row. Youngest player gets First Player marker.

END OF EXCERPT - For full rules, see complete rulebook.
EOF

chown ga:ga "$RULEBOOK_PATH"

echo "✅ Rulebook excerpt created at: $RULEBOOK_PATH"

# Create a blank document to start with
cat > /tmp/create_game_doc.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
import sys

doc = Document()

# Add a simple instruction paragraph
doc.add_paragraph("Create a one-page quick reference for the board game described in the rulebook excerpt.")
doc.add_paragraph("")
doc.add_paragraph("Your reference sheet should include:")
doc.add_paragraph("  • Turn Structure section")
doc.add_paragraph("  • Common Actions section")
doc.add_paragraph("  • Phase Reference section")
doc.add_paragraph("")
doc.add_paragraph("Use headings, bold text, and lists to make it easy to scan during gameplay.")

doc.save(sys.argv[1])
print(f"Document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_game_doc.py
python3 /tmp/create_game_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_gameref_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_gameref_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Board Game Quick Reference Task Setup Complete ==="
echo "📝 Task Instructions:"
echo "  Create a one-page quick reference sheet for the board game."
echo "  "
echo "  Required sections:"
echo "    1. Turn Structure - sequence of phases"
echo "    2. Common Actions - what players can do"
echo "    3. Phase Reference - quick reminders for each phase"
echo "  "
echo "  Formatting requirements:"
echo "    • Use heading styles for section titles"
echo "    • Use bold text for emphasis on key terms"
echo "    • Use bullet points or numbered lists for clarity"
echo "    • Keep it concise (under 1000 words for one-page reference)"
echo "  "
echo "  Reference material available at: $RULEBOOK_PATH"
echo "  Edit and save to: $DOC_PATH"
echo "  "
echo "  Save with Ctrl+S when complete."