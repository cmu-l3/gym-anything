#!/bin/bash
set -euo pipefail

echo "=== Setting up Theater Playbill Formatting Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

sudo -u ga mkdir -p /home/ga/Documents

# Create the raw playbill document
cat << 'PYEOF' > /tmp/create_raw_playbill.py
from docx import Document
from docx.shared import Inches, Pt

doc = Document()

# Set to standard US Letter, 1 inch margins (to be changed by agent)
section = doc.sections[0]
section.page_width = Inches(8.5)
section.page_height = Inches(11.0)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)

# Main Title - plain text
doc.add_paragraph("The Importance of Being Earnest")
doc.add_paragraph("By Oscar Wilde")
doc.add_paragraph("")

# Section 1
doc.add_paragraph("Director's Note")
doc.add_paragraph("Welcome to the Riverside Community Theater's production of Oscar Wilde's masterpiece. This play is a trivial comedy for serious people, and we have endeavored to bring its sharp wit and brilliant social commentary to life. Our cast has worked tirelessly over the last eight weeks to perfect the rapid-fire dialogue and farcical timing that makes this piece so enduringly hilarious. Thank you for supporting local arts!")
doc.add_paragraph("")

# Section 2
doc.add_paragraph("Cast of Characters")
doc.add_paragraph("John Worthing, J.P. - played by Arthur Pendelton")
doc.add_paragraph("Algernon Moncrieff - played by Simon Lewis")
doc.add_paragraph("Rev. Canon Chasuble, D.D. - played by Martin Hughes")
doc.add_paragraph("Merriman, Butler - played by Thomas Wright")
doc.add_paragraph("Lane, Manservant - played by Edward Barnes")
doc.add_paragraph("Lady Bracknell - played by Margaret Sterling")
doc.add_paragraph("Hon. Gwendolen Fairfax - played by Sarah Jenkins")
doc.add_paragraph("Cecily Cardew - played by Emily Rostova")
doc.add_paragraph("Miss Prism, Governess - played by Beatrice O'Connor")
doc.add_paragraph("")

# Section 3
doc.add_paragraph("Act Synopsis")
doc.add_paragraph("Act I: Algernon Moncrieff's Flat in Half-Moon Street, W. The curtain rises on a luxurious London apartment where Algernon receives his friend Ernest (who is actually Jack Worthing). Jack intends to propose to Algernon's cousin, Gwendolen. Algernon discovers Jack's double life.")
doc.add_paragraph("Act II: The Garden at the Manor House, Woolton. Jack returns to his country estate to 'kill off' his fictitious brother Ernest, only to find that Algernon has arrived posing as the infamous Ernest to woo Jack's ward, Cecily.")
doc.add_paragraph("Act III: Drawing-Room at the Manor House. Lady Bracknell arrives to investigate the engagements. Mysteries of birth are resolved in a surprising revelation involving a handbag at Victoria Station.")
doc.add_paragraph("")

# Section 4
doc.add_paragraph("Cast Biographies")
doc.add_paragraph("Arthur Pendelton - Arthur is thrilled to return to the Riverside stage after his performance as Macbeth last season. He has a BFA in Theater from State University and works as an architect.")
doc.add_paragraph("Simon Lewis - Simon is making his community theater debut. By day, he is a high school literature teacher. He dedicates this performance to his very own Gwendolen.")
doc.add_paragraph("Margaret Sterling - A veteran of the stage, Margaret has performed in over 40 local productions. Her favorite roles include Lady Macbeth and Madame Arcati. She thanks her cats for listening to her run lines.")
doc.add_paragraph("Sarah Jenkins - Sarah recently graduated with a degree in performing arts. She is excited to bring Gwendolen's sophisticated snobbery to life.")
doc.add_paragraph("Emily Rostova - Emily has been acting since she was seven. She finds Cecily's diary-keeping habits highly relatable and hopes you enjoy the show.")

doc.save('/home/ga/Documents/raw_playbill.docx')
PYEOF

python3 /tmp/create_raw_playbill.py
chown ga:ga /home/ga/Documents/raw_playbill.docx

# Make sure WPS isn't already running
pkill -f wps || true
sleep 1

# Launch WPS Writer with the raw document
echo "Launching WPS Writer..."
su - ga -c "DISPLAY=:1 wps /home/ga/Documents/raw_playbill.docx &"
sleep 5

# Wait for window and maximize
WID=$(get_wps_window_id)
if [ -n "$WID" ]; then
    echo "Found WPS window: $WID"
    focus_window "$WID"
    
    # Dismiss EULA and any initial dialogs
    dismiss_wps_dialogs
    
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
else
    echo "Warning: Could not detect WPS window"
fi

# Take initial state screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="