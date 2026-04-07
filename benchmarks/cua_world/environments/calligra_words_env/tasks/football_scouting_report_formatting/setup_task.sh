#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Football Scouting Report Task ==="

# Prepare directories
install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

# Clean state
kill_calligra_processes
rm -f /home/ga/Documents/wildcats_scouting_report.odt
rm -f /home/ga/Desktop/scouting_report_style.txt
rm -f /tmp/task_start_time.txt
rm -f /tmp/task_result.json

# Create the style guide
cat > /home/ga/Desktop/scouting_report_style.txt << 'EOF'
WEEK 8 SCOUTING REPORT STYLE GUIDE

1. TITLE: The main document title ("WEEK 8 SCOUTING REPORT: WILDCATS") must be Centered, Bold, and >=16pt font.
2. MAIN SECTIONS: Apply the "Heading 1" style to the following 6 main sections:
   - Offensive Overview
   - Defensive Overview
   - Special Teams
   - Key Personnel
   - Tendency Analysis
   - Keys to Victory
3. SUBSECTIONS: Apply the "Heading 2" style to the 6 positional subsections under Key Personnel:
   - Quarterbacks
   - Running Backs
   - Wide Receivers
   - Defensive Line
   - Linebackers
   - Secondary
4. TABLES: Convert the comma-separated data under "Key Offensive Playmakers" and "Key Defensive Playmakers" into two structured tables.
5. SELECTIVE BOLDING: Bold the following schematic play concepts wherever they appear in the body paragraphs (do NOT bold the surrounding text):
   - Mesh
   - Y-Cross
   - Cover 3
   - Tampa 2
   - Fire Zone
   - Pin and Pull
6. LISTS: Format the items under "Tendency Analysis" as a bulleted list. Format the items under "Keys to Victory" as a numbered list.
7. ALIGNMENT: Justify the alignment of the standard body paragraphs.
EOF
chown ga:ga /home/ga/Desktop/scouting_report_style.txt

# Create the completely unformatted ODT file
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

add_paragraph("WEEK 8 SCOUTING REPORT: WILDCATS")
add_paragraph("")
add_paragraph("Offensive Overview")
add_paragraph("The Wildcats run a spread offensive system heavily reliant on quick game and RPO concepts. They want to get the ball to their playmakers in space. We need to be prepared for their favorite concepts, especially Mesh and Y-Cross, which they use to attack man coverage.")
add_paragraph("")
add_paragraph("Defensive Overview")
add_paragraph("They base out of a 4-2-5 alignment and primarily play Cover 3 and Tampa 2 in the secondary. On third down, expect them to bring the Fire Zone blitz to pressure the quarterback. They are disciplined in their run fits and will use Pin and Pull schemes to get their linebackers flowing fast.")
add_paragraph("")
add_paragraph("Special Teams")
add_paragraph("Their kicker has a strong leg but struggles with accuracy beyond 40 yards. The punter is left-footed, so our returners need to adjust to the spin.")
add_paragraph("")
add_paragraph("Key Personnel")
add_paragraph("")
add_paragraph("Quarterbacks")
add_paragraph("Their starter is a dual-threat player who extends plays with his legs.")
add_paragraph("")
add_paragraph("Running Backs")
add_paragraph("A downhill runner who excels between the tackles.")
add_paragraph("")
add_paragraph("Wide Receivers")
add_paragraph("Speed on the outside, excellent route runners in the slot.")
add_paragraph("")
add_paragraph("Defensive Line")
add_paragraph("Big, physical interior defenders who eat up double teams.")
add_paragraph("")
add_paragraph("Linebackers")
add_paragraph("Fast, undersized group that plays sideline to sideline.")
add_paragraph("")
add_paragraph("Secondary")
add_paragraph("Aggressive corners who like to press, safeties are heavy hitters.")
add_paragraph("")
add_paragraph("Key Offensive Playmakers")
add_paragraph("POS, Name, Number, Height/Weight, Notes")
add_paragraph("QB, Marcus Johnson, 2, 6-2/215, Dual-threat extends plays")
add_paragraph("RB, DeAndre Swift, 4, 5-10/210, Elusive in open field")
add_paragraph("WR, Justin Jefferson, 1, 6-1/195, Primary target on third down")
add_paragraph("")
add_paragraph("Key Defensive Playmakers")
add_paragraph("POS, Name, Number, Height/Weight, Notes")
add_paragraph("DE, Aidan Hutchinson, 97, 6-6/265, Elite pass rusher")
add_paragraph("LB, Fred Warner, 54, 6-3/230, Coverage specialist")
add_paragraph("CB, Jalen Ramsey, 5, 6-1/190, Will travel with WR1")
add_paragraph("")
add_paragraph("Tendency Analysis")
add_paragraph("High frequency of play-action on first down.")
add_paragraph("They go for it on 4th and short inside our 40.")
add_paragraph("Heavy blitz tendency on 3rd and long.")
add_paragraph("")
add_paragraph("Keys to Victory")
add_paragraph("Stop the run on early downs.")
add_paragraph("Limit explosive plays in the passing game.")
add_paragraph("Win the turnover margin.")

doc.save("/home/ga/Documents/wildcats_scouting_report.odt")
PYEOF

chown ga:ga /home/ga/Documents/wildcats_scouting_report.odt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words directly targeting the document
launch_calligra_document "/home/ga/Documents/wildcats_scouting_report.odt" "/tmp/calligra_launch.log"

# Wait for UI to load and maximize
wait_for_window "Calligra Words" 30
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Zoom in slightly for better agent visibility
    DISPLAY=:1 xdotool key ctrl+equal
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+equal
fi

take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="