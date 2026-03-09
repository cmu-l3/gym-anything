#!/bin/bash
# setup_task.sh - Newsletter Linked Frames Flow

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Newsletter Linked Frames Task ==="

# 1. Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. Generate the source document (newsletter_draft.odt)
# We generate content in DOCX first using python-docx (easier API), 
# then convert to ODT to ensure we start with a clean native ODT file.
# This ensures frame linking features work correctly.

cat << 'PYEOF' > /tmp/generate_newsletter.py
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# --- Page 1 Content ---
title = doc.add_paragraph("Community Garden Quarterly")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = title.runs[0]
run.bold = True
run.font.size = Pt(24)
run.font.name = "Liberation Sans"

subtitle = doc.add_paragraph("Spring 2024 Edition")
subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
subtitle.runs[0].italic = True

doc.add_paragraph("")

# The Target Story (to be moved)
# Currently just sitting in the body
heading = doc.add_paragraph("Letter from the President")
heading.style = "Heading 1"

body_text = (
    "As we welcome the first green shoots of spring, it is a time for renewal and growth "
    "in our shared community spaces. This past winter was harsh, but our compost systems "
    "maintained steady heat, a testament to the dedication of our Weekend Warriors team. "
    "I want to extend a special thanks to Sarah and Mike for their work on the north shed repairs.\n\n"
    "Looking ahead, we have ambitious plans for the season. The new rainwater catchment system "
    "installation begins next month. This project, funded by the City Green Grant, will "
    "reduce our municipal water usage by 40%. We are also expanding the pollinator pathway "
    "along the fence line to support our local bee population.\n\n"
    "However, we face challenges as well. Membership dues are due by the 15th, and we still "
    "have 15 plots available for the lottery. Please spread the word to neighbors who might "
    "be interested in growing their own organic produce. Remember, a garden is not just about "
    "tomatoes and basil; it is about cultivating relationships and rooting ourselves in the community.\n\n"
    "Finally, a reminder about the upcoming Spring Fling potluck. Sign-up sheets are posted "
    "on the shed door. Let's make this our best season yet!"
)
doc.add_paragraph(body_text)

doc.add_paragraph("")
doc.add_paragraph("--- End of Page 1 Content ---")

# Insert Page Break to ensure document has 2 pages
doc.add_page_break()

# --- Page 2 Content ---
doc.add_paragraph("Upcoming Events Calendar")
doc.add_paragraph("March 15: Seed Swap")
doc.add_paragraph("April 02: Fence Painting Day")
doc.add_paragraph("April 22: Earth Day Celebration")

doc.save("/tmp/newsletter_draft.docx")
PYEOF

# Run generation script
python3 /tmp/generate_newsletter.py

# Convert DOCX to ODT (LibreOffice native format)
# We use headless LibreOffice for this conversion
echo "Converting draft to ODT format..."
libreoffice --headless --convert-to odt --outdir /home/ga/Documents /tmp/newsletter_draft.docx

# Clean up temp
rm /tmp/generate_newsletter.py /tmp/newsletter_draft.docx
chown ga:ga /home/ga/Documents/newsletter_draft.odt

# 3. Record initial state
date +%s > /tmp/task_start_time.txt
echo "Initial state recorded."

# 4. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/newsletter_draft.odt > /tmp/writer_launch.log 2>&1 &"

# 5. Wait for window and maximize
wait_for_window "LibreOffice Writer" 60
sleep 2

WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

# Dismiss any startup dialogs (like "Tip of the Day")
safe_xdotool ga :1 key Escape
sleep 0.5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="