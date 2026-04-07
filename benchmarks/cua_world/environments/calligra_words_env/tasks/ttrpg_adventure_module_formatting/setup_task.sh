#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up TTRPG Adventure Module Formatting Task ==="

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/ashen_king_module.odt
rm -f /home/ga/Desktop/module_style_guide.txt

# ------------------------------------------------------------------
# Create the style guide
# ------------------------------------------------------------------
cat << 'EOF' > /home/ga/Desktop/module_style_guide.txt
MODULE FORMATTING STYLE GUIDE

Please apply the following layout rules to prepare the adventure for publication:

1. TITLE:
   The main title ("The Crypt of the Ashen King") must be Centered, Bold, and at least 18pt font.

2. HEADING HIERARCHY:
   - Chapter Titles ("Introduction", "The Crypt") must be Heading 1.
   - Area Titles ("Area 1: The Obsidian Doors", "Area 2...", etc.) must be Heading 2.
   - Monster Names must be Heading 3. IMPORTANT: You must delete the "STAT BLOCK: " prefix from these names!

3. READ-ALOUD TEXT:
   Game Masters read these descriptions aloud to players.
   - Locate all paragraphs wrapped in [READ ALOUD] and [END READ] tags.
   - DELETE the [READ ALOUD] and [END READ] tags completely.
   - Format the descriptive paragraph: apply Italic text AND increase the Left Margin (indent) to set it apart from standard text.

4. STAT BLOCKS:
   Make the mechanical labels Bold, but leave the values normal. 
   Specifically, bold these exact phrases:
   - "Armor Class:"
   - "Hit Points:"
   - "Speed:"
   - "Actions:"

5. ENCOUNTER SUMMARY TABLE:
   Convert the raw pipe-delimited text section at the end of the document into a formal 4-column Table.
EOF
chown ga:ga /home/ga/Desktop/module_style_guide.txt

# ------------------------------------------------------------------
# Create the unformatted adventure module using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title
add_paragraph("The Crypt of the Ashen King")
add_paragraph("An Adventure for 3rd-Level Characters")
add_paragraph("")

# H1
add_paragraph("Introduction")
add_paragraph("Hidden beneath the Smoldering Peaks lies the ancient resting place of a warlord who sought immortality through elemental fire. Known as the Ashen King, his crypt has recently been unsealed by cultists seeking to harness his power.")
add_paragraph("")

# H1
add_paragraph("The Crypt")
add_paragraph("The dungeon walls are made of dark volcanic rock. The air is stiflingly hot, smelling of sulfur and old dust.")
add_paragraph("")

# H2
add_paragraph("Area 1: The Obsidian Doors")
add_paragraph("[READ ALOUD]")
add_paragraph("The heavy stone doors are warm to the touch. Carved into their surface is the visage of a screaming man wreathed in flames. The faint glow of embers seeps through the crack between the doors.")
add_paragraph("[END READ]")
add_paragraph("The doors are barred from the inside but can be forced open with a successful Strength check. Two cultists stand guard just inside.")
add_paragraph("")

# H3 (with prefix to be removed)
add_paragraph("STAT BLOCK: Ashen Cultist")
add_paragraph("Armor Class: 13 (leather armor)")
add_paragraph("Hit Points: 16 (3d8 + 3)")
add_paragraph("Speed: 30 ft.")
add_paragraph("Actions: Scimitar. Melee Weapon Attack: +4 to hit, reach 5 ft., one target. Hit: 5 (1d6 + 2) slashing damage plus 2 (1d4) fire damage.")
add_paragraph("")

# H2
add_paragraph("Area 2: The Hall of Whispers")
add_paragraph("[READ ALOUD]")
add_paragraph("Eerie whispers echo through this long hall. The floor is covered in a thick layer of pale gray ash that seems to stir even when there is no breeze. At the far end stands a hulking construct made entirely of charred bones.")
add_paragraph("[END READ]")
add_paragraph("The ash makes this area difficult terrain. The bone golem animates if anyone steps further than 10 feet into the room.")
add_paragraph("")

# H3
add_paragraph("STAT BLOCK: Bone Golem")
add_paragraph("Armor Class: 14 (natural armor)")
add_paragraph("Hit Points: 45 (6d8 + 18)")
add_paragraph("Speed: 20 ft.")
add_paragraph("Actions: Slam. Melee Weapon Attack: +5 to hit, reach 5 ft., one target. Hit: 10 (2d6 + 3) bludgeoning damage.")
add_paragraph("")

# H2
add_paragraph("Area 3: The Throne Room")
add_paragraph("[READ ALOUD]")
add_paragraph("A massive figure sits slumped upon a throne of fused bone and black iron. Suddenly, the eye sockets of the skull flare with orange fire, and the Ashen King rises, hefting a massive greataxe.")
add_paragraph("[END READ]")
add_paragraph("The Ashen King fights until destroyed. The room contains several braziers that deal fire damage if pushed over.")
add_paragraph("")

# H3
add_paragraph("STAT BLOCK: The Ashen King")
add_paragraph("Armor Class: 16 (chain mail)")
add_paragraph("Hit Points: 65 (10d8 + 20)")
add_paragraph("Speed: 30 ft.")
add_paragraph("Actions: Greataxe. Melee Weapon Attack: +6 to hit, reach 5 ft., one target. Hit: 11 (1d12 + 4) slashing damage plus 4 (1d8) fire damage.")
add_paragraph("")

# Table section
add_paragraph("Encounter Summary")
add_paragraph("Area | Encounter | Difficulty | XP")
add_paragraph("Area 1 | 2 Ashen Cultists | Easy | 100")
add_paragraph("Area 2 | 1 Bone Golem | Hard | 450")
add_paragraph("Area 3 | The Ashen King | Deadly | 1100")
add_paragraph("")

doc.save("/home/ga/Documents/ashen_king_module.odt")
PYEOF

chown ga:ga /home/ga/Documents/ashen_king_module.odt

# Launch Calligra Words and warm it up
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/ashen_king_module.odt >/tmp/calligra_words_launch.log 2>&1 < /dev/null &"

# Wait for Calligra to open
wait_for_window "Calligra Words" 30

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Dismiss any startup dialogs if they pop up
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Give UI time to stabilize
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "=== Task Setup Complete ==="