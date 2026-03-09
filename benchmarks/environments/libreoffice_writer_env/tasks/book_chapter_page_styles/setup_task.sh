#!/bin/bash
# setup_task.sh - Book Chapter Manuscript Page Styles

source /workspace/scripts/task_utils.sh

echo "=== Setting up Book Chapter Page Styles Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Create the draft document with python-docx
# We create a "raw" document: default margins, single spacing, no headers, no styles
echo "Generating draft document..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Set default uniform margins (1 inch) to start with
section = doc.sections[0]
section.left_margin = Inches(1.0)
section.right_margin = Inches(1.0)
section.top_margin = Inches(1.0)
section.bottom_margin = Inches(1.0)

# Add Chapter Title (Plain text initially, agent must style it)
p_title = doc.add_paragraph("Chapter I")
p_title.alignment = WD_ALIGN_PARAGRAPH.LEFT # Agent must Center
run_title = p_title.runs[0]
run_title.font.name = "Liberation Sans" # Wrong font
run_title.font.size = Pt(12)
run_title.bold = False # Agent must apply Heading 1

doc.add_paragraph("")

# Add Body Text (Pride and Prejudice, Ch 1)
body_text = [
    "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
    "However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.",
    "\"My dear Mr. Bennet,\" said his lady to him one day, \"have you heard that Netherfield Park is let at last?\"",
    "Mr. Bennet replied that he had not.",
    "\"But it is,\" returned she; \"for Mrs. Long has just been here, and she told me all about it.\"",
    "Mr. Bennet made no answer.",
    "\"Do you not want to know who has taken it?\" cried his wife impatiently.",
    "\"You want to tell me, and I have no objection to hearing it.\"",
    "This was invitation enough.",
    "\"Why, my dear, you must know, Mrs. Long says that Netherfield is taken by a young man of large fortune from the north of England; that he came down on Monday in a chaise and four to see the place, and was so much delighted with it, that he agreed with Mr. Morris immediately; that he is to take possession before Michaelmas, and some of his servants are to be in the house by the end of next week.\"",
    "\"What is his name?\"",
    "\"Bingley.\"",
    "\"Is he married or single?\"",
    "\"Oh! single, my dear, to be sure! A single man of large fortune; four or five thousand a year. What a fine thing for our girls!\"",
    "\"How so? How can it affect them?\"",
    "\"My dear Mr. Bennet,\" replied his wife, \"how can you be so tiresome! You must know that I am thinking of his marrying one of them.\"",
    "\"Is that his design in settling here?\"",
    "\"Design! Nonsense, how can you talk so! But it is very likely that he may fall in love with one of them, and therefore you must visit him as soon as he comes.\"",
    "\"I see no occasion for that. You and the girls may go, or you may send them by themselves, which perhaps will be still better, for as you are as handsome as any of them, Mr. Bingley may like you the best of the party.\"",
    "\"My dear, you flatter me. I certainly have had my share of beauty, but I do not pretend to be anything extraordinary now. When a woman has five grown-up daughters, she ought to give over thinking of her own beauty.\"",
    "\"In such cases, a woman has not often much beauty to think of.\"",
    "\"But, my dear, you must indeed go and see Mr. Bingley when he comes into the neighbourhood.\"",
    "\"It is more than I engage for, I assure you.\"",
    "\"But consider your daughters. Only think what an establishment it would be for one of them. Sir William and Lady Lucas are determined to go, merely on that account, for in general, you know, they visit no new comers. Indeed you must go, for it will be impossible for us to visit him if you do not.\"",
    "\"You are over-scrupulous, surely. I dare say Mr. Bingley will be very glad to see you; and I will send a few lines by you to assure him of my hearty consent to his marrying whichever he chooses of the girls; though I must throw in a good word for my little Lizzy.\""
]

# Add enough text to ensure we span at least 3 pages when double-spaced
# (Repeating the text if necessary to generate pages for even/odd check)
full_text = body_text * 3 

for para in full_text:
    p = doc.add_paragraph(para)
    p.paragraph_format.line_spacing = 1.0 # Single spacing (Agent must change to 2.0)
    for run in p.runs:
        run.font.name = "Liberation Sans"
        run.font.size = Pt(10) # Agent must change to 12

doc.save("/home/ga/Documents/chapter1_draft.docx")
print("Created /home/ga/Documents/chapter1_draft.docx")
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/chapter1_draft.docx

# Start LibreOffice Writer
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/chapter1_draft.docx > /dev/null 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "chapter1_draft" 30

# Maximize window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid"
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
    focus_window "$wid"
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="