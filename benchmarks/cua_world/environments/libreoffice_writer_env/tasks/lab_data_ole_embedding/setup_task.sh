#!/bin/bash
# setup_task.sh for lab_data_ole_embedding

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Lab Data OLE Embedding Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the initial ODT document using python-odfpy (if available) or raw python
# Since the environment has odfpy, we utilize it to create a clean ODT.
# If odfpy fails, we fall back to creating a basic FODT (Flat XML ODT) text file.

sudo -u ga mkdir -p /home/ga/Documents

cat << 'PYEOF' > /tmp/create_doc.py
import sys
try:
    from odf.opendocument import OpenDocumentText
    from odf.style import Style, TextProperties, ParagraphProperties
    from odf.text import H, P, Span

    doc = OpenDocumentText()

    # Create styles
    h1style = Style(name="Heading 1", family="paragraph")
    h1style.addElement(TextProperties(attributes={'fontsize':"18pt",'fontweight':"bold"}))
    doc.styles.addElement(h1style)

    # Content
    doc.text.addElement(H(outlinelevel=1, stylename=h1style, text="Chemical Synthesis Batch Report"))
    doc.text.addElement(P(text="Date: October 24, 2023"))
    doc.text.addElement(P(text="Technician: J. Doe"))
    doc.text.addElement(P(text=""))
    
    doc.text.addElement(H(outlinelevel=2, text="1.0 Executive Summary"))
    doc.text.addElement(P(text="This report summarizes the production yields for the Alpha-7 synthesis campaign. Three batches were processed using the standard catalytic reduction protocol."))
    doc.text.addElement(P(text=""))

    doc.text.addElement(H(outlinelevel=2, text="2.0 Methodology"))
    doc.text.addElement(P(text="Reactants were introduced into the 500L reactor at controlled rates. Temperature was maintained at 75°C for 4 hours."))
    doc.text.addElement(P(text=""))

    doc.text.addElement(H(outlinelevel=2, text="3.0 Yield Analysis"))
    doc.text.addElement(P(text="Please insert the yield data analysis below using a spreadsheet object for calculation accuracy."))
    doc.text.addElement(P(text=""))
    doc.text.addElement(P(text="[INSERT YIELD DATA HERE]"))
    doc.text.addElement(P(text=""))

    doc.text.addElement(H(outlinelevel=2, text="4.0 Conclusion"))
    doc.text.addElement(P(text="Preliminary results indicate consistent yields across all batches."))

    doc.save("/home/ga/Documents/batch_synthesis_report.odt", addsuffix=False)
    print("Created ODT file successfully")
except Exception as e:
    print(f"Error creating ODT: {e}")
    sys.exit(1)
PYEOF

echo "Generating starting document..."
python3 /tmp/create_doc.py

# Set permissions
chown ga:ga /home/ga/Documents/batch_synthesis_report.odt

# Start LibreOffice Writer
echo "Starting LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/batch_synthesis_report.odt > /dev/null 2>&1 &"
fi

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "batch_synthesis_report" 30

# Maximize and focus
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Focusing window $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss "What's New" or recovery dialogs if they appear
    sleep 2
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="