#!/bin/bash
set -euo pipefail

echo "=== Setting up Paperback Book Layout Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Clean up previous runs
rm -f /home/ga/Documents/crystal_crypt_print_ready.odt 2>/dev/null || true

# Generate the Source ODT file
# We use a Python script with odfpy to create a valid ODT structure
# If odfpy is not installed in the environment, we install it first (it should be per install_writer.sh)
echo "Generating manuscript..."
python3 << 'PYEOF'
import os
import sys

try:
    from odf.opendocument import OpenDocumentText
    from odf.style import Style, TextProperties, ParagraphProperties
    from odf.text import H, P, Span
except ImportError:
    print("odfpy not found, attempting to use simple text or exit")
    sys.exit(0) # Logic handled by fallback if needed, but assuming env has it

doc = OpenDocumentText()

# Create styles
h1style = Style(name="Heading 1", family="paragraph")
h1style.addElement(TextProperties(attributes={'fontsize':"14pt",'fontweight':"bold"}))
h1style.addElement(ParagraphProperties(attributes={'breakbefore':"page"}))
doc.styles.addElement(h1style)

# Content - The Crystal Crypt by Philip K. Dick (Public Domain)
# Shortened version for the task
chapters = [
    ("CHAPTER I", [
        "Stark and cold, the Martian landscape stretched out before him.",
        "Use of the Trans-Terran space shuttle was strictly forbidden to non-citizens, "
        "but Erickson didn't care. He had a job to do.",
        "The red dust swirled against the viewport."
    ]),
    ("CHAPTER II", [
        "The interior of the city was a stark contrast to the wastes outside.",
        "Lights flickered in the subterranean passages.",
        "'We need to move,' said Mara, checking her chronometer."
    ]),
    ("CHAPTER III", [
        "They reached the central hub just as the alarms began to sound.",
        "Erickson pulled the data drive from his pocket.",
        "'This is it,' he whispered. 'The proof we need.'"
    ])
]

# Add Title Page content
doc.text.addElement(P(text="THE CRYSTAL CRYPT"))
doc.text.addElement(P(text=""))
doc.text.addElement(P(text="By Philip K. Dick"))
doc.text.addElement(P(text=""))
doc.text.addElement(P(text="Draft Manuscript - Standard A4 Layout"))

# Add Chapters
for title, paragraphs in chapters:
    # Heading 1 style is crucial for the "Chapter Name" field to work later
    h = H(outlinelevel=1, stylename=h1style, text=title)
    doc.text.addElement(h)
    for p_text in paragraphs:
        doc.text.addElement(P(text=p_text))

output_path = "/home/ga/Documents/crystal_crypt_draft.odt"
doc.save(output_path)
print(f"Created {output_path}")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/crystal_crypt_draft.odt
chmod 666 /home/ga/Documents/crystal_crypt_draft.odt

# Launch LibreOffice Writer with the file
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/crystal_crypt_draft.odt > /tmp/writer_task.log 2>&1 &"

# Wait for process
wait_for_process "soffice" 15

# Wait for window
if ! wait_for_window "LibreOffice Writer" 60; then
    wait_for_window "crystal_crypt" 30 || true
fi

# Maximize window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs (like Tip of the Day)
sleep 2
safe_xdotool ga :1 key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Instructions:"
echo "1. Change page size to 6x9 inches"
echo "2. Set margins to Mirrored (Inner 0.8, Outer 0.5)"
echo "3. Configure alternating headers with dynamic fields (Page #, Chapter Name)"
echo "4. Save as /home/ga/Documents/crystal_crypt_print_ready.odt"