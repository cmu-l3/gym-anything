#!/bin/bash
set -e
echo "=== Setting up Screenplay Formatting Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory and clean up
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/Nebula_Frontier_Sc3.odt 2>/dev/null || true
rm -f /home/ga/Documents/scene_draft.txt 2>/dev/null || true
rm -f /home/ga/Documents/style_guide.txt 2>/dev/null || true

# 2. Create the Raw Text Draft
cat > /home/ga/Documents/scene_draft.txt << 'EOF'
INT. BRIDGE - DAY

The bridge is chaotic. ALARM KLAXONS blare rhythmically. Smoke pours from the ops console.

CMDR. CHEN
Report!

LT. SPARKS
(coughing)
Shields are down to twelve percent! I can't lock down the surge!

CMDR. CHEN
Reroute auxiliary power to the forward deflectors. Do it now!

LT. SPARKS
I'm trying, Commander! The coupling is fused.

The ship ROCKS violently. Sparks shower from the ceiling.

SHIP COMPUTER (V.O.)
Hull breach detected on Deck 4. Sealing bulkheads.

CMDR. CHEN
Get us out of here. Engage jump drive.

LT. SPARKS
Coordinates?

CMDR. CHEN
Anywhere but here. Punch it!
EOF

# 3. Create the Style Guide
cat > /home/ga/Documents/style_guide.txt << 'EOF'
NEBULA FRONTIER - FORMATTING GUIDELINES
---------------------------------------
All scripts must be formatted in Apache OpenOffice Writer using custom Styles.
Do NOT use the space bar or tabs to center text. You must define and apply Paragraph Styles.

FONT: Courier New, 12pt (For ALL styles)

1. SCENE HEADING
   - Font Style: Bold, All Caps
   - Alignment: Left
   - Indent: 0"
   - Spacing: 1 line space before

2. ACTION
   - Font Style: Regular
   - Alignment: Left
   - Indent: 0"

3. CHARACTER
   - Font Style: All Caps
   - Alignment: Left
   - Indentation Before Text (Left Indent): 2.0" (approx 5.0 cm)

4. DIALOGUE
   - Font Style: Regular
   - Alignment: Left
   - Indentation Before Text (Left Indent): 1.0" (approx 2.5 cm)
   - Indentation After Text (Right Indent): 1.5" (approx 3.8 cm)

5. PARENTHETICAL
   - Font Style: Regular
   - Alignment: Left
   - Indentation Before Text (Left Indent): 1.5" (approx 3.8 cm)

INSTRUCTIONS:
1. Open 'scene_draft.txt'.
2. Open the Styles and Formatting panel (F11).
3. Create the styles above.
4. Apply them to the text.
5. Save as 'Nebula_Frontier_Sc3.odt'.
EOF

# Set permissions
chown ga:ga /home/ga/Documents/scene_draft.txt
chown ga:ga /home/ga/Documents/style_guide.txt

# 4. Create Desktop Shortcut for Writer (if not exists)
if [ ! -f "/home/ga/Desktop/openoffice-writer.desktop" ]; then
    mkdir -p /home/ga/Desktop
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=openoffice4-writer
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
fi

# 5. Record start time and initial state
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="