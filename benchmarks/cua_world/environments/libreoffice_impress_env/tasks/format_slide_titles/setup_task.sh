#!/bin/bash
set -e
echo "=== Setting up format_slide_titles task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

PRES_DIR="/home/ga/Documents/Presentations"
PRES_FILE="$PRES_DIR/staff_meeting.pptx"

# Create directory
sudo -u ga mkdir -p "$PRES_DIR"

# Create the initial presentation with inconsistent formatting using python-pptx
# We embed the python script to ensure the file is generated fresh
cat > /tmp/create_presentation.py << 'PYEOF'
#!/usr/bin/env python3
"""Create a staff meeting presentation with inconsistent title formatting."""

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

prs = Presentation()

# Slide layout: Title + Content
slide_layout = prs.slide_layouts[1]

slides_data = [
    {
        "title": "Weekly Staff Meeting - October 14, 2024",
        "font_name": "Times New Roman",
        "font_size": Pt(28),
        "font_color": RGBColor(0x8B, 0x00, 0x00),  # Dark red
        "font_bold": False,
        "bullets": [
            "Welcome and attendance check — please sign in on the shared sheet",
            "Review of action items from October 7 meeting",
            "Department updates: Engineering, Marketing, Finance, Operations",
            "Guest speaker: VP of Product on Q4 roadmap priorities"
        ]
    },
    {
        "title": "Project Status Updates",
        "font_name": "Courier New",
        "font_size": Pt(40),
        "font_color": RGBColor(0x00, 0x64, 0x00),  # Dark green
        "font_bold": True,
        "bullets": [
            "CRM Migration: 78% complete, on track for November 1 deadline",
            "Mobile App v3.2: Beta testing phase, 142 bug reports triaged",
            "Data Center Consolidation: Vendor selection finalized, contract review in progress",
            "Customer Portal Redesign: UX research complete, wireframes under review"
        ]
    },
    {
        "title": "Budget and Resource Allocation",
        "font_name": "DejaVu Serif",
        "font_size": Pt(24),
        "font_color": RGBColor(0x00, 0x00, 0x00),  # Black
        "font_bold": False,
        "bullets": [
            "Q3 spending: $2.4M of $2.8M budget utilized (85.7%)",
            "Q4 forecast: Additional $180K requested for cloud infrastructure scaling",
            "Headcount: 3 open positions — 2 Senior Engineers, 1 Project Manager",
            "Training budget: $45K remaining, prioritize security certification program"
        ]
    },
    {
        "title": "Key Challenges and Risks",
        "font_name": "Liberation Mono",
        "font_size": Pt(32),
        "font_color": RGBColor(0x80, 0x00, 0x80),  # Purple
        "font_bold": True,
        "bullets": [
            "Supply chain delays impacting hardware refresh timeline by 3 weeks",
            "Single sign-on integration blocked by legacy authentication system",
            "Staff turnover in QA team creating bottleneck for release testing",
            "Regulatory compliance audit scheduled for November 15 — preparation needed"
        ]
    },
    {
        "title": "Action Items and Next Steps",
        "font_name": "Nimbus Sans L",
        "font_size": Pt(20),
        "font_color": RGBColor(0xFF, 0x8C, 0x00),  # Dark orange
        "font_bold": False,
        "bullets": [
            "Sarah: Finalize vendor contract for data center project by October 18",
            "DevOps team: Complete staging environment setup for CRM migration testing",
            "HR: Schedule interviews for open Senior Engineer positions this week",
            "All managers: Submit Q4 budget adjustments to Finance by October 21"
        ]
    },
]

for sd in slides_data:
    slide = prs.slides.add_slide(slide_layout)

    # Set title with inconsistent formatting
    title_shape = slide.shapes.title
    title_shape.text = ""  # Clear default
    tf = title_shape.text_frame
    tf.clear()
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.LEFT
    run = p.add_run()
    run.text = sd["title"]
    run.font.name = sd["font_name"]
    run.font.size = sd["font_size"]
    run.font.color.rgb = sd["font_color"]
    run.font.bold = sd["font_bold"]

    # Set bullet points with consistent formatting (should not be changed)
    body_shape = slide.placeholders[1]
    tf_body = body_shape.text_frame
    tf_body.clear()
    for i, bullet_text in enumerate(sd["bullets"]):
        if i == 0:
            p = tf_body.paragraphs[0]
        else:
            p = tf_body.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        run = p.add_run()
        run.text = bullet_text
        run.font.name = "Liberation Sans"
        run.font.size = Pt(18)
        run.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
        run.font.bold = False

output_path = "/home/ga/Documents/Presentations/staff_meeting.pptx"
prs.save(output_path)
PYEOF

echo "Generating initial presentation..."
python3 /tmp/create_presentation.py
chown ga:ga "$PRES_FILE"

# Store initial file hash for anti-gaming (to check if file was actually touched)
md5sum "$PRES_FILE" | awk '{print $1}' > /tmp/initial_file_hash.txt

# Open presentation in LibreOffice Impress
echo "Opening presentation in LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$PRES_FILE' > /dev/null 2>&1 &"

# Wait for LibreOffice window
wait_for_window "staff_meeting" 60 || wait_for_window "LibreOffice Impress" 60

# Maximize and focus
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss potential recovery or tip of the day dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="