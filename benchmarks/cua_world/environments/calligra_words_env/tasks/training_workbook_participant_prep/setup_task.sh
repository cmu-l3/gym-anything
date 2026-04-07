#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Training Workbook Prep Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/leadership_training_master.odt

# ------------------------------------------------------------------
# Create the unformatted Master Training Guide using odfpy
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title
add_paragraph("Conflict Resolution & Authentic Leadership")
add_paragraph("Participant & Facilitator Master Guide")
add_paragraph("Version 2.4")
add_paragraph("")

# --- MODULE 1 ---
add_paragraph("Module 1: The Foundations of Authentic Leadership")
add_paragraph("[FACILITATOR NOTE: Ask the room to define authenticity before showing the next slide. Spend 5 minutes here and write answers on the whiteboard.]")
add_paragraph("Authentic leadership is an approach to leadership that emphasizes building the leader's legitimacy through honest relationships with followers.")
add_paragraph("")
add_paragraph("Defining Authenticity")
add_paragraph("Authenticity means being true to your own personality, values, and spirit, regardless of the pressure that you're under to act otherwise.")
add_paragraph("[TRAINER INSTRUCTION: Distribute Handout 1.A now. Give participants 3 minutes to read it silently.]")
add_paragraph("")
add_paragraph("Personal Action Plan - Module 1")
add_paragraph("Goal	Action Steps	Target Date")
add_paragraph("	 	 ")
add_paragraph("	 	 ")
add_paragraph("")

# --- MODULE 2 ---
add_paragraph("Module 2: Identifying Conflict Styles")
add_paragraph("[FACILITATOR NOTE: Share a personal story about a time you mishandled a conflict early in your career to build vulnerability.]")
add_paragraph("Conflict is an inevitable part of workplace dynamics. How we respond to it dictates our success as leaders.")
add_paragraph("")
add_paragraph("The Five Conflict Styles")
add_paragraph("Based on the Thomas-Kilmann Conflict Mode Instrument, there are five major styles of conflict management: Competing, Accommodating, Avoiding, Collaborating, and Compromising.")
add_paragraph("[TRAINER INSTRUCTION: Break the room into 5 groups. Assign one conflict style to each group to discuss.]")
add_paragraph("")
add_paragraph("Recognizing Your Default Style")
add_paragraph("We all have a default style we revert to under stress. Recognizing it is the first step to modulating your response.")
add_paragraph("")
add_paragraph("Personal Action Plan - Module 2")
add_paragraph("Goal	Action Steps	Target Date")
add_paragraph("	 	 ")
add_paragraph("	 	 ")
add_paragraph("")

# --- MODULE 3 ---
add_paragraph("Module 3: Active Listening and Empathy")
add_paragraph("Active listening requires fully concentrating, understanding, responding, and then remembering what is being said.")
add_paragraph("[FACILITATOR NOTE: Roleplay exercise. Divide into pairs. One person is the speaker, the other is the listener. 10 minutes.]")
add_paragraph("")
add_paragraph("The Empathetic Pivot")
add_paragraph("Moving from a defensive posture to an empathetic one requires intentional mental pivoting during heated conversations.")
add_paragraph("[TRAINER INSTRUCTION: Play the audio clip of the 'bad' vs 'good' listening example from the shared drive.]")
add_paragraph("")
add_paragraph("Personal Action Plan - Module 3")
add_paragraph("Goal	Action Steps	Target Date")
add_paragraph("	 	 ")
add_paragraph("	 	 ")
add_paragraph("")

# --- MODULE 4 ---
add_paragraph("Module 4: Resolution Frameworks")
add_paragraph("[FACILITATOR NOTE: Remind the class that frameworks are guidelines, not rigid rules. Adaptability is key.]")
add_paragraph("Having a structured approach to conflict resolution ensures that emotions do not derail the conversation.")
add_paragraph("")
add_paragraph("The EAR Framework")
add_paragraph("Empathy, Attention, Respect (EAR) is a foundational framework for de-escalating tense situations.")
add_paragraph("[TRAINER INSTRUCTION: Have participants complete the end-of-day survey before leaving the room.]")
add_paragraph("")
add_paragraph("Personal Action Plan - Module 4")
add_paragraph("Goal	Action Steps	Target Date")
add_paragraph("	 	 ")
add_paragraph("	 	 ")
add_paragraph("")

doc.save("/home/ga/Documents/leadership_training_master.odt")
PYEOF

chown ga:ga /home/ga/Documents/leadership_training_master.odt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/leadership_training_master.odt >/tmp/calligra.log 2>&1 < /dev/null &"

# Wait for Calligra window
wait_for_window "Calligra Words" 30

# Maximize and Focus
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="