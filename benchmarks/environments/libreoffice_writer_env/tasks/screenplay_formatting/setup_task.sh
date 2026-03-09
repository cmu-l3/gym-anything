#!/bin/bash
# setup_task.sh - Screenplay Formatting Task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Screenplay Formatting Task ==="

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure Document directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Create the unformatted screenplay draft using python-docx
# This ensures we have a clean "bad" state to start from
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Set "wrong" margins (1.0 inch all around)
section = doc.sections[0]
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)

# Helper to add text with "wrong" font (Liberation Serif, 11pt)
def add_para(text, bold=False):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = "Liberation Serif"
    run.font.size = Pt(11)
    run.bold = bold
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT # Everything improperly left-aligned
    return p

# --- Screenplay Content (The Tell-Tale Heart Adaptation) ---

add_para("FADE IN:") # Transition (should be right aligned)
add_para("")

add_para("INT. OLD MAN'S BEDROOM - NIGHT") # Scene Heading (should be Heading 1)
add_para("")

add_para("The room is pitch black. A single ray of light from a lantern cuts across the darkness, illuminating a sleeping OLD MAN's face. Specifically, his PALE BLUE EYE.")
add_para("")

add_para("NARRATOR (V.O.)") # Character (should be centered)
add_para("It is impossible to say how first the idea entered my brain; but once conceived, it haunted me day and night.")
add_para("")

add_para("The lantern beam wavers slightly.")
add_para("")

add_para("NARRATOR (V.O.)")
add_para("Object there was none. Passion there was none. I loved the old man. He had never wronged me. He had never given me insult. For his gold I had no desire.")
add_para("")

add_para("CUT TO:") # Transition
add_para("")

add_para("INT. HOUSE - HALLWAY - NIGHT") # Scene Heading
add_para("")

add_para("The NARRATOR stands outside the bedroom door. He is perfectly still. He moves the latch. It makes NO SOUND.")
add_para("")

add_para("NARRATOR")
add_para("I think it was his eye! yes, it was this! He had the eye of a vulture --a pale blue eye, with a film over it.")
add_para("")

add_para("CUT TO:") # Transition
add_para("")

add_para("INT. OLD MAN'S BEDROOM - DAY") # Scene Heading
add_para("")

add_para("Police officers are searching the room. They pull up floorboards. The NARRATOR sits on a chair, smiling confidently. Three officers: OFFICER DUPIN, OFFICER 2, and OFFICER 3.")
add_para("")

add_para("OFFICER DUPIN")
add_para("The neighbors heard a shriek during the night. Suspicion of foul play had been aroused.")
add_para("")

add_para("NARRATOR")
add_para("The old man, I mentioned, was absent in the country. I took my visitors all over the house. I bade them search - search well.")
add_para("")

add_para("The Narrator taps his foot rhythmically. A sound begins. Low, dull, quick. Like a watch enveloped in cotton.")
add_para("")

add_para("OFFICER 2")
add_para("Is something wrong, sir? You look pale.")
add_para("")

add_para("NARRATOR")
add_para("No! I gasped for breath. I talked more quickly -- more vehemently. But the noise steadily increased.")
add_para("")

add_para("The sound gets LOUDER. THUMP-THUMP. THUMP-THUMP.")
add_para("")

add_para("NARRATOR")
add_para("Villains! Dissemble no more! I admit the deed! --tear up the planks! here, here! --It is the beating of his hideous heart!")
add_para("")

add_para("FADE OUT.") # Transition

doc.save("/home/ga/Documents/screenplay_draft.docx")
print("Created unformatted screenplay draft.")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/screenplay_draft.docx
chmod 666 /home/ga/Documents/screenplay_draft.docx

# Ensure no output file exists yet
rm -f /home/ga/Documents/screenplay_formatted.docx

# Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/screenplay_draft.docx > /tmp/writer.log 2>&1 &"

# Wait for Writer to start
wait_for_window "LibreOffice Writer" 60 || echo "WARNING: Window wait timeout"

# Maximize the window for the agent
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for debugging/verification
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="