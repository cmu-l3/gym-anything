#!/bin/bash
set -euo pipefail

echo "=== Setting up Transcript Style Chaining Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_count.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw ODT transcript using python-odfpy
# We use Python to ensure a valid ODT file structure
echo "Generating raw transcript document..."
cat << 'PYEOF' | sudo -u ga python3 -
from odf.opendocument import OpenDocumentText
from odf.text import P
from odf.style import Style, TextProperties, ParagraphProperties

def create_raw_transcript():
    doc = OpenDocumentText()
    
    # Create content - simulated City Council minutes
    # Pattern: Speaker line (ends in :) followed by text
    content = [
        "Mayor Johnson:",
        "I call this regular meeting of the City Council to order. The time is 6:00 PM. City Clerk, please call the roll.",
        "City Clerk Williams:",
        "Councilmember Davis? Present. Councilmember Chen? Present. Councilmember Rodriguez? Present. Mayor Johnson? Present. All members are present, Mr. Mayor.",
        "Mayor Johnson:",
        "Thank you. The first item on the agenda is the approval of minutes from the February 14th meeting. Do I hear a motion?",
        "Councilmember Davis:",
        "I move to approve the minutes as submitted.",
        "Councilmember Chen:",
        "I second the motion.",
        "Mayor Johnson:",
        "It has been moved and seconded. Is there any discussion? Hearing none, all those in favor say Aye.",
        "Council (Unanimous):",
        "Aye.",
        "Mayor Johnson:",
        "Opposed, Nay? The Ayes have it. The minutes are approved. We move now to New Business, Item 4A: Proposed rezoning of the Riverfront District.",
        "Councilmember Rodriguez:",
        "Mr. Mayor, I have reviewed the proposal and the community feedback. While I support development, I am concerned about the traffic impact study. It seems to rely on data from three years ago.",
        "Planning Director Smith:",
        "Councilmember, valid point. We used the 2021 baseline because 2022 and 2023 showed anomalous patterns due to construction on Main Street. We believe the 2021 data, adjusted for 2% annual growth, is actually more predictive.",
        "Councilmember Rodriguez:",
        "I appreciate that clarification. However, I would still like to see a current spot-check count done this month before we vote.",
        "Mayor Johnson:",
        "A reasonable request. Director, can you have that ready by the next meeting?",
        "Planning Director Smith:",
        "Yes, Mr. Mayor. We can conduct a 48-hour count next Tuesday and Wednesday.",
        "Mayor Johnson:",
        "Excellent. We will table Item 4A until the next session. Next item."
    ]
    
    # Add paragraphs using standard default style
    for line in content:
        doc.text.addElement(P(text=line))
        
    doc.save("/home/ga/Documents/council_minutes_raw.odt")
    print("Created /home/ga/Documents/council_minutes_raw.odt")

if __name__ == "__main__":
    create_raw_transcript()
PYEOF

# Ensure permissions
chmod 666 /home/ga/Documents/council_minutes_raw.odt

# Launch LibreOffice Writer with the file
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/council_minutes_raw.odt > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "council_minutes_raw" 60

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    focus_window "$WID"
fi

# Dismiss any "Tip of the Day" or recovery dialogs
sleep 2
safe_xdotool ga :1 key Escape
sleep 0.5
safe_xdotool ga :1 key Escape

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="