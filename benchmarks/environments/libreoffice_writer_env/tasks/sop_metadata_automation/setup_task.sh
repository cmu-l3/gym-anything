#!/bin/bash
set -e
echo "=== Setting up SOP Metadata Automation Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 1. Generate the initial 'Legacy' SOP document with static headers using python-odf (odfpy)
# We use a python script to ensure a valid ODT structure
cat << 'PYEOF' > /tmp/create_sop.py
import os
from odf.opendocument import OpenDocumentText
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, Header, ParagraphProperties
from odf.text import P, Span

def create_sop():
    doc = OpenDocumentText()

    # --- Styles ---
    # Create a layout that includes a header
    pl = PageLayout(name="pagelayout")
    doc.automaticstyles.addElement(pl)
    plp = PageLayoutProperties(margintop="2cm", marginbottom="2cm", marginleft="2cm", marginright="2cm")
    pl.addElement(plp)
    
    # Create the master page
    mp = MasterPage(name="Standard", pagelayoutname=pl)
    doc.masterstyles.addElement(mp)
    
    # Create the Header content (Static Text initially)
    header = Header()
    # Style for header paragraph (centered, grey, small)
    header_style = Style(name="HeaderPara", family="paragraph")
    header_style.addElement(ParagraphProperties(textalign="center"))
    header_style.addElement(TextProperties(fontsize="9pt", color="#555555"))
    doc.styles.addElement(header_style)
    
    # Static text mimicking what the agent needs to replace
    # "Title: Steam Sterilization Protocol | Doc #: SOP-805 | Rev: 1.0"
    p = P(stylename=header_style)
    p.addText("Title: Steam Sterilization Protocol  |  Doc #: SOP-805  |  Rev: 1.0")
    header.addElement(p)
    mp.addElement(header)

    # --- Body Content ---
    h1style = Style(name="Heading1", family="paragraph")
    h1style.addElement(TextProperties(fontsize="16pt", fontweight="bold"))
    doc.styles.addElement(h1style)

    body_style = Style(name="BodyText", family="paragraph")
    body_style.addElement(TextProperties(fontsize="11pt"))
    doc.styles.addElement(body_style)

    # Add content
    doc.text.addElement(P(stylename=h1style, text="1. Purpose"))
    doc.text.addElement(P(stylename=body_style, text="The purpose of this procedure is to define the steam sterilization process for surgical instruments to ensure sterility assurance level (SAL) of 10^-6."))

    doc.text.addElement(P(stylename=h1style, text="2. Scope"))
    doc.text.addElement(P(stylename=body_style, text="This SOP applies to all autoclaves located in Building B, Production Area."))

    doc.text.addElement(P(stylename=h1style, text="3. Responsibilities"))
    doc.text.addElement(P(stylename=body_style, text="- Quality Assurance: Review and approve cycle parameters."))
    doc.text.addElement(P(stylename=body_style, text="- Operations: Load and unload autoclave according to diagram."))

    doc.text.addElement(P(stylename=h1style, text="4. Procedure"))
    doc.text.addElement(P(stylename=body_style, text="4.1. Pre-conditioning: Ensure chamber is empty and drain is clear."))
    doc.text.addElement(P(stylename=body_style, text="4.2. Loading: Place instrument trays on rack. Do not stack."))
    doc.text.addElement(P(stylename=body_style, text="4.3. Cycle Selection: Select Cycle B (121°C for 15 minutes)."))
    doc.text.addElement(P(stylename=body_style, text="4.4. Unloading: Allow to cool to <40°C before handling."))

    doc.save("/home/ga/Documents/SOP_805_Sterilization.odt")
    print("SOP document created successfully.")

if __name__ == "__main__":
    create_sop()
PYEOF

echo "Generating initial SOP document..."
python3 /tmp/create_sop.py
chown ga:ga /home/ga/Documents/SOP_805_Sterilization.odt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start LibreOffice Writer
echo "Starting LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer /home/ga/Documents/SOP_805_Sterilization.odt > /tmp/writer.log 2>&1 &"
    
    # Wait for window
    wait_for_window "LibreOffice Writer" 60 || echo "Warning: Window wait timeout"
fi

# Maximize window
echo "Maximizing window..."
sleep 5
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="