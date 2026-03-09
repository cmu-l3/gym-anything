#!/bin/bash
set -e
echo "=== Setting up Incident Report Table Formatting Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# -----------------------------------------------------------------------------
# Generate the Draft Document (Real Data)
# -----------------------------------------------------------------------------
# We use a python script to generate a messy DOCX file with realistic content
# but bad formatting (Courier New, no styles, wide margins).

cat > /tmp/generate_aar_draft.py << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Set intentionally wrong margins (1.25 inches) to test margin correction
for section in doc.sections:
    section.top_margin = Inches(1.25)
    section.bottom_margin = Inches(1.25)
    section.left_margin = Inches(1.25)
    section.right_margin = Inches(1.25)

def add_para(text, bold=False):
    """Add paragraph in Courier New 10pt - intentionally bad formatting."""
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.name = "Courier New"
    run.font.size = Pt(10)
    run.bold = bold
    return p

# ---- TITLE ----
add_para("AFTER-ACTION REPORT", bold=True)
add_para("Multi-Alarm Structure Fire — 1847 Industrial Parkway — October 14, 2023")
add_para("")

# ---- INCIDENT SUMMARY ----
add_para("Incident Summary", bold=True)
add_para("")
add_para(
    "On Saturday, October 14, 2023, at approximately 0623 hours, the Metro City Fire Department "
    "was dispatched to a reported structure fire at 1847 Industrial Parkway, a two-story "
    "commercial warehouse facility of approximately 28,000 square feet. The building, constructed "
    "in 1974, featured Type II non-combustible construction with a steel bar-joist roof system, "
    "concrete masonry unit (CMU) exterior walls, and a partial mezzanine level used for office space."
)
add_para("")
add_para(
    "First-arriving units found heavy smoke showing from the Charlie side (rear) of the structure "
    "with fire visible through two loading dock doors on the Delta side. A second alarm was "
    "transmitted at 0634 hours due to fire extension into the mezzanine level. The incident was "
    "elevated to a third alarm at 0651 hours when a partial roof collapse was observed. "
    "The fire was declared under control at 0847 hours."
)
add_para("")

# ---- INCIDENT TIMELINE (Plaintext to be converted to table) ----
add_para("Incident Timeline", bold=True)
add_para("")
add_para("The following timeline reconstructs key events from dispatch records.")
add_para("")

timeline_entries = [
    "0623 | Dispatch | Box alarm transmitted for reported structure fire at 1847 Industrial Parkway",
    "0627 | Engine 7 | En route from Station 7 with 4 personnel; assigned as first-due engine",
    "0629 | Truck 3 | En route from Station 3 with 4 personnel; assigned as first-due truck",
    "0631 | Engine 7 | On scene; Captain Morales reports heavy smoke from Charlie side",
    "0632 | Engine 7 | 1-3/4 inch handline deployed to Alpha side entrance; crew making entry",
    "0633 | Truck 3 | On scene; beginning 360-degree size-up; fire visible through Delta side",
    "0634 | Battalion 2 | On scene; assumes Incident Command; transmits second alarm",
    "0636 | Engine 12 | On scene on second alarm; assigned to Delta side exposure protection",
    "0651 | Battalion 2 | Partial roof collapse observed; third alarm transmitted",
    "0655 | Engine 7 | Interior crews evacuated; PAR conducted — all personnel accounted for",
    "0847 | Battalion 2 | Fire declared under control; overhaul operations commenced",
]

for entry in timeline_entries:
    add_para(entry)

add_para("")

# ---- TACTICAL OPERATIONS ----
add_para("Tactical Operations", bold=True)
add_para("")

add_para("Fire Suppression", bold=True)
add_para("")
add_para(
    "Initial fire attack was conducted by Engine 7's crew using a 1-3/4 inch handline advanced "
    "through the main Alpha-side entrance. Conditions on the ground floor were immediately "
    "challenging, with near-zero visibility and rapidly increasing thermal conditions."
)
add_para("")

add_para("Search and Rescue", bold=True)
add_para("")
add_para(
    "Primary search of the ground floor was initiated by Truck 3 at 0639 hours. "
    "Rescue 1 was assigned to search the mezzanine level upon arrival at 0645 hours. "
    "Due to the transition to defensive operations at 0651 hours, the mezzanine search was suspended."
)
add_para("")

add_para("Ventilation", bold=True)
add_para("")
add_para(
    "Horizontal ventilation was provided by Truck 3's outside team. Vertical ventilation "
    "was not initiated due to the steel bar-joist roof construction and early indication "
    "of structural compromise."
)
add_para("")

# ---- PERSONNEL AND EQUIPMENT ----
add_para("Personnel and Equipment", bold=True)
add_para("")
add_para(
    "A total of 67 personnel responded on the three-alarm assignment, operating 12 apparatus "
    "including 6 engine companies, 2 truck companies, 1 tower company, 2 rescue companies, "
    "and 3 chief officer vehicles."
)
add_para("")

# ---- FINDINGS AND RECOMMENDATIONS ----
add_para("Findings and Recommendations", bold=True)
add_para("")
add_para(
    "Finding 1: The building's wet-pipe sprinkler system was rendered ineffective due to a "
    "partially closed OS&Y control valve. Post-incident inspection confirmed the valve "
    "was approximately 75% closed."
)
add_para("")

add_para("Recommendations for Training", bold=True)
add_para("")
add_para(
    "Recommendation 1: Conduct a department-wide refresher on sprinkler system impairment "
    "recognition during commercial structure fire operations."
)
add_para("")

# ---- CONCLUSION ----
add_para("Conclusion", bold=True)
add_para("")
add_para(
    "The multi-alarm fire at 1847 Industrial Parkway represents a significant incident that "
    "tested the department's capabilities. The impaired sprinkler system was the most "
    "significant contributing factor to fire spread."
)
add_para("")
add_para("Report date: November 2, 2023")

doc.save("/home/ga/Documents/aar_draft.docx")
PYEOF

echo "Generating draft document..."
python3 /tmp/generate_aar_draft.py

# Set ownership
chown ga:ga /home/ga/Documents/aar_draft.docx
rm -f /home/ga/Documents/aar_formatted.docx 2>/dev/null || true

# -----------------------------------------------------------------------------
# Launch Application
# -----------------------------------------------------------------------------

# Start LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/aar_draft.docx > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "aar_draft" 30

# Maximize and Focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo "Focusing window ID: $wid"
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
    focus_window "$wid"
    
    # Dismiss any initial dialogs (like "Tip of the Day")
    sleep 2
    safe_xdotool ga :1 key Escape
    sleep 1
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="