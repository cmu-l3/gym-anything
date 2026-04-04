#!/bin/bash
set -e
echo "=== Setting up Replace Presentation Fonts task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents/Presentations

PPTX_FILE="/home/ga/Documents/Presentations/department_meeting.pptx"

# Create the initial presentation with Courier New fonts using python-pptx
# We run this as python inside the container since python-pptx is installed there
cat > /tmp/create_presentation.py << 'PYEOF'
#!/usr/bin/env python3
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.enum.text import PP_ALIGN
from pptx.dml.color import RGBColor

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

COURIER = "Courier New"

def add_textbox(slide, left, top, width, height, text, font_size=16, bold=False, alignment=PP_ALIGN.LEFT, color=RGBColor(0x33, 0x33, 0x33)):
    """Add a textbox with Courier New font."""
    txBox = slide.shapes.add_textbox(Emu(left), Emu(top), Emu(width), Emu(height))
    tf = txBox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.name = COURIER
    p.font.size = Pt(font_size)
    p.font.bold = bold
    p.font.color.rgb = color
    p.alignment = alignment
    return tf

def add_paragraph(tf, text, font_size=16, bold=False, level=0, color=RGBColor(0x33, 0x33, 0x33)):
    """Add a paragraph with Courier New font."""
    p = tf.add_paragraph()
    p.text = text
    p.font.name = COURIER
    p.font.size = Pt(font_size)
    p.font.bold = bold
    p.font.color.rgb = color
    p.level = level
    return p

# ---- Slide 1: Title Slide ----
slide1 = prs.slides.add_slide(prs.slide_layouts[6])  # Blank layout
tf1_title = add_textbox(slide1,
    left=Inches(1.5), top=Inches(1.8), width=Inches(10.3), height=Inches(2),
    text="Q3 Department Meeting",
    font_size=36, bold=True, alignment=PP_ALIGN.CENTER,
    color=RGBColor(0x1A, 0x3C, 0x6E))

tf1_sub = add_textbox(slide1,
    left=Inches(2), top=Inches(3.8), width=Inches(9.3), height=Inches(1.5),
    text="Marketing Division — September 15, 2024",
    font_size=20, alignment=PP_ALIGN.CENTER,
    color=RGBColor(0x55, 0x55, 0x55))

add_paragraph(tf1_sub, "Presented by: Regional Marketing Team", font_size=16, color=RGBColor(0x77, 0x77, 0x77))
add_paragraph(tf1_sub, "Confidential — Internal Use Only", font_size=12, color=RGBColor(0x99, 0x99, 0x99))

# ---- Slide 2: Campaign Performance ----
slide2 = prs.slides.add_slide(prs.slide_layouts[6])
tf2_title = add_textbox(slide2,
    left=Inches(0.8), top=Inches(0.5), width=Inches(11.7), height=Inches(1),
    text="Campaign Performance",
    font_size=28, bold=True, color=RGBColor(0x1A, 0x3C, 0x6E))

tf2_body = add_textbox(slide2,
    left=Inches(1), top=Inches(1.6), width=Inches(11), height=Inches(5),
    text="Website traffic increased 23% quarter-over-quarter, reaching 1.4 million unique visitors",
    font_size=16)

bullets_s2 = [
    "Email open rates averaged 28.7%, exceeding the industry benchmark of 21.3%",
    "Social media engagement grew by 31% driven by the new video content strategy",
    "Paid search campaigns generated 4,200 qualified leads at $12.40 cost per lead",
]
for bullet in bullets_s2:
    add_paragraph(tf2_body, bullet, font_size=16)

# ---- Slide 3: Upcoming Initiatives ----
slide3 = prs.slides.add_slide(prs.slide_layouts[6])
tf3_title = add_textbox(slide3,
    left=Inches(0.8), top=Inches(0.5), width=Inches(11.7), height=Inches(1),
    text="Upcoming Initiatives",
    font_size=28, bold=True, color=RGBColor(0x1A, 0x3C, 0x6E))

tf3_body = add_textbox(slide3,
    left=Inches(1), top=Inches(1.6), width=Inches(11), height=Inches(5),
    text="Launch integrated holiday campaign across all digital channels by October 15",
    font_size=16)

bullets_s3 = [
    "Redesign landing pages for product lines using updated brand guidelines and A/B testing",
    "Expand influencer partnership program to include 12 new micro-influencers in Q4",
]
for bullet in bullets_s3:
    add_paragraph(tf3_body, bullet, font_size=16)

# ---- Slide 4: Action Items and Deadlines ----
slide4 = prs.slides.add_slide(prs.slide_layouts[6])
tf4_title = add_textbox(slide4,
    left=Inches(0.8), top=Inches(0.5), width=Inches(11.7), height=Inches(1),
    text="Action Items and Deadlines",
    font_size=28, bold=True, color=RGBColor(0x1A, 0x3C, 0x6E))

tf4_body = add_textbox(slide4,
    left=Inches(1), top=Inches(1.6), width=Inches(11), height=Inches(5),
    text="Finalize Q4 budget allocation across channels — Owner: Sarah Chen — Due: Sept 22",
    font_size=16)

bullets_s4 = [
    "Submit holiday campaign creative briefs to design team — Owner: Marcus Rivera — Due: Sept 25",
    "Complete vendor evaluation for new analytics platform — Owner: Priya Patel — Due: Oct 1",
    "Distribute updated brand guidelines to all regional teams — Owner: James Okafor — Due: Oct 5",
]
for bullet in bullets_s4:
    add_paragraph(tf4_body, bullet, font_size=16)

prs.save('/home/ga/Documents/Presentations/department_meeting.pptx')
PYEOF

# Generate the PPTX
echo "Generating presentation file..."
python3 /tmp/create_presentation.py
chown ga:ga "$PPTX_FILE"

# Store initial file hash to detect if file is just overwritten with same data
md5sum "$PPTX_FILE" > /tmp/initial_file_hash.txt

# Start Impress with the file
echo "Starting LibreOffice Impress..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --impress '$PPTX_FILE' &"
fi

# Wait for window
wait_for_window "department_meeting" 30 || wait_for_window "Impress" 15

# Maximize window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
focus_window "department_meeting" 2>/dev/null || focus_window "Impress" 2>/dev/null || true

# Dismiss any potential dialogs (Tip of the day, etc)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="