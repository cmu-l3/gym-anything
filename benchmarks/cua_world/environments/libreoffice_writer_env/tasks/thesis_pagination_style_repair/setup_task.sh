#!/bin/bash
set -e
echo "=== Setting up Thesis Pagination Repair Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Record task start time
date +%s > /tmp/task_start_time.txt

# Generate the messy thesis draft using python-docx
# We use Python here to ensure the DOCX internal structure has the specific 
# flaws (manual breaks) and styles we want to test.
cat << 'PYEOF' > /tmp/gen_thesis.py
import os
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_BREAK

def create_messy_thesis(path):
    doc = Document()
    
    # 1. Setup Styles
    styles = doc.styles
    
    # Heading 1: Reset flow props (simulate bad state)
    # This forces the user to fix it in the style definition
    h1 = styles['Heading 1']
    h1.paragraph_format.page_break_before = False
    h1.font.size = Pt(24)
    h1.font.name = 'Liberation Sans'
    
    # Heading 2: Reset flow props
    h2 = styles['Heading 2']
    h2.paragraph_format.keep_with_next = False
    h2.font.size = Pt(18)
    h2.font.name = 'Liberation Sans'

    # Body Text: Create/Reset
    if 'Body Text' not in styles:
        bt = styles.add_style('Body Text', 1) # 1 = PARAGRAPH type
    else:
        bt = styles['Body Text']
    bt.base_style = styles['Normal']
    bt.paragraph_format.widow_control = False  # BAD STATE
    bt.font.size = Pt(12)
    bt.font.name = 'Liberation Serif'
    bt.paragraph_format.space_after = Pt(12)

    # 2. Add Content
    # Chapter 1
    doc.add_paragraph('Chapter 1: Introduction', style='Heading 1')
    doc.add_paragraph('This is the introduction to the thesis. It discusses the problem statement and significance of the study.', style='Body Text')
    # Add filler content
    filler = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ' * 5
    doc.add_paragraph(filler, style='Body Text')
    doc.add_paragraph(filler, style='Body Text')
    
    doc.add_paragraph('1.1 Background of Study', style='Heading 2')
    doc.add_paragraph(filler, style='Body Text')

    # INSERT MANUAL BREAK (The flaw to fix)
    # Ideally, Heading 1 should force a break, but here we simulate a user hitting Ctrl+Enter
    run = doc.add_paragraph().add_run()
    run.add_break(WD_BREAK.PAGE)

    # Chapter 2
    doc.add_paragraph('Chapter 2: Literature Review', style='Heading 1')
    doc.add_paragraph('Here we review existing literature regarding layout algorithms and document processing.', style='Body Text')
    doc.add_paragraph(filler, style='Body Text')

    doc.add_paragraph('2.1 Historical Context', style='Heading 2')
    doc.add_paragraph(filler, style='Body Text')
    doc.add_paragraph(filler, style='Body Text')

    # INSERT MANUAL BREAK
    run = doc.add_paragraph().add_run()
    run.add_break(WD_BREAK.PAGE)

    # Chapter 3
    doc.add_paragraph('Chapter 3: Methodology', style='Heading 1')
    doc.add_paragraph('3.1 Data Collection', style='Heading 2')
    doc.add_paragraph(filler, style='Body Text')
    
    doc.save(path)
    print(f"Created {path}")

create_messy_thesis('/home/ga/Documents/thesis_draft.docx')
PYEOF

# Execute generation
python3 /tmp/gen_thesis.py
rm /tmp/gen_thesis.py

# Set permissions
chown ga:ga "/home/ga/Documents/thesis_draft.docx"

# Launch LibreOffice Writer with the document
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer \"/home/ga/Documents/thesis_draft.docx\" > /tmp/writer.log 2>&1 &"

# Wait for window using task_utils.sh function
wait_for_window "LibreOffice Writer" 60
wait_for_window "thesis_draft" 20

# Get Window ID
WID=$(get_writer_window_id)

if [ -n "$WID" ]; then
    echo "Focusing window $WID..."
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss potential "Tip of the Day"
    sleep 2
    safe_xdotool ga :1 key Escape 2>/dev/null || true
    
    # Open Styles sidebar (F11) to help the agent
    safe_xdotool ga :1 key F11 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="