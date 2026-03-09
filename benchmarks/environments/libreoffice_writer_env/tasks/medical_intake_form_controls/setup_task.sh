#!/bin/bash
set -e
echo "=== Setting up Medical Intake Form task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Define paths
DOCS_DIR="/home/ga/Documents"
DRAFT_FILE="$DOCS_DIR/intake_form_draft.odt"
mkdir -p "$DOCS_DIR"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create the draft ODT using python-odfpy (installed in env)
# We use python to generate a clean ODT structure with text labels but no controls
echo "Generating draft document..."
python3 -c "
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P, H, Span

doc = OpenDocumentText()

# Styles
s_header = Style(name='Header1', family='paragraph')
s_header.addElement(ParagraphProperties(textalign='center'))
s_header.addElement(TextProperties(fontsize='18pt', fontweight='bold', fontfamily='Arial'))
doc.styles.addElement(s_header)

s_label = Style(name='Label', family='text')
s_label.addElement(TextProperties(fontweight='bold', fontsize='12pt'))
doc.automaticstyles.addElement(s_label)

s_para = Style(name='Standard', family='paragraph')
s_para.addElement(ParagraphProperties(marginbottom='0.2in'))
doc.styles.addElement(s_para)

# Content
h = H(outlinelevel=1, stylename=s_header, text='Amani Family Health - New Patient Registration')
doc.text.addElement(h)
doc.text.addElement(P(text=''))

# Section 1: Demographics
doc.text.addElement(P(text='Please complete the following information:', stylename=s_para))

p1 = P(stylename=s_para)
p1.addElement(Span(text='Full Name: ', stylename=s_label))
doc.text.addElement(p1)

p2 = P(stylename=s_para)
p2.addElement(Span(text='Date of Birth: ', stylename=s_label))
doc.text.addElement(p2)

doc.text.addElement(P(text=''))

# Section 2: Gender
p3 = P(stylename=s_para)
p3.addElement(Span(text='Gender (Select one):', stylename=s_label))
doc.text.addElement(p3)
# Spaces used to simulate layout where controls should go
doc.text.addElement(P(text='          Male          Female          Non-Binary'))

doc.text.addElement(P(text=''))

# Section 3: History
p4 = P(stylename=s_para)
p4.addElement(Span(text='Medical History (Check all that apply):', stylename=s_label))
doc.text.addElement(p4)
doc.text.addElement(P(text='          Asthma'))
doc.text.addElement(P(text='          Diabetes'))
doc.text.addElement(P(text='          Hypertension'))

doc.save('$DRAFT_FILE')
"

# Set permissions
chown ga:ga "$DRAFT_FILE"

# Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer \"$DRAFT_FILE\" > /dev/null 2>&1 &"
    
    # Wait for window
    wait_for_window "LibreOffice Writer" 30 || wait_for_window "intake_form" 30
fi

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r "$WID" -i -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="