#!/bin/bash
# setup_task.sh — Legal Pleading Line Numbering Task

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Legal Pleading Task ==="

# Record task start timestamp for verifier
date +%s > /tmp/task_start_time
chown ga:ga /tmp/task_start_time 2>/dev/null || true

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the "messy" draft document
# We use python-docx to generate a file with:
# - Calibri 11pt (wrong)
# - Single spacing (wrong)
# - 1.0 inch margins all around (Left is wrong)
# - No line numbers (wrong)
# - No page numbers (wrong)
# - Manual bold headings instead of styles (wrong)

echo "Generating motion_draft.docx..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Set "Wrong" Default Style: Calibri 11pt
style = doc.styles['Normal']
font = style.font
font.name = 'Calibri'
font.size = Pt(11)

# Set "Wrong" Spacing: Single
paragraph_format = style.paragraph_format
paragraph_format.line_spacing = 1.0
paragraph_format.space_after = Pt(0)

# Set "Wrong" Margins: 1 inch all around
for section in doc.sections:
    section.left_margin = Inches(1.0)
    section.right_margin = Inches(1.0)
    section.top_margin = Inches(1.0)
    section.bottom_margin = Inches(1.0)

# Content Generation
# Caption
p = doc.add_paragraph("SUPERIOR COURT OF THE STATE OF CALIFORNIA")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.runs[0].bold = True

p = doc.add_paragraph("COUNTY OF LOS ANGELES")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.runs[0].bold = True
doc.add_paragraph("")

# Case Info
doc.add_paragraph("ROBERTO MARTINEZ,\nPlaintiff,")
doc.add_paragraph("v.")
doc.add_paragraph("PACIFIC COAST PROPERTY MANAGEMENT, INC., and DOES 1-50,\nDefendants.")
doc.add_paragraph("")
doc.add_paragraph("Case No. 23STCV04817")
doc.add_paragraph("")

# Title
p = doc.add_paragraph("NOTICE OF MOTION AND MOTION TO COMPEL FURTHER RESPONSES TO SPECIAL INTERROGATORIES, SET ONE")
p.runs[0].bold = True
doc.add_paragraph("")

# Notice text
doc.add_paragraph(
    "TO ALL PARTIES AND THEIR ATTORNEYS OF RECORD: PLEASE TAKE NOTICE that on April 15, 2024, "
    "at 8:30 a.m., or as soon thereafter as the matter may be heard in Department 30 of the "
    "above-entitled Court, Plaintiff Roberto Martinez will and hereby does move for an order "
    "compelling Defendant Pacific Coast Property Management, Inc. to provide further verified "
    "responses to Plaintiff’s Special Interrogatories, Set One, Nos. 5, 8, 12, and 14."
)
doc.add_paragraph("")

# MEMORANDUM (Heading - Manual Bold, no style)
p = doc.add_paragraph("MEMORANDUM OF POINTS AND AUTHORITIES")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.runs[0].bold = True
doc.add_paragraph("")

# Intro text
doc.add_paragraph(
    "Discovery in California is a matter of right unless a specific statutory exemption applies. "
    "Under Code of Civil Procedure § 2017.010, a party may obtain discovery regarding any "
    "matter, not privileged, that is relevant to the subject matter involved in the pending "
    "action. This right to discovery is construed liberally in favor of disclosure. "
    "(Williams v. Superior Court (2017) 3 Cal.5th 531, 540.)"
)
doc.add_paragraph("")

# STATEMENT OF FACTS
p = doc.add_paragraph("STATEMENT OF FACTS")
p.runs[0].bold = True
doc.add_paragraph(
    "This action arises from a slip-and-fall incident that occurred on February 12, 2023, "
    "at the apartment complex located at 450 N. Rossmore Ave, Los Angeles. Plaintiff alleges "
    "that Defendant negligently maintained the common area stairwell, allowing a persistent "
    "water leak to create a hazardous condition. On November 10, 2023, Plaintiff served "
    "Special Interrogatories, Set One. Defendant served responses on December 15, 2023, "
    "consisting entirely of boilerplate objections without substantive factual information."
)
doc.add_paragraph("")

# ARGUMENT
p = doc.add_paragraph("ARGUMENT")
p.runs[0].bold = True
doc.add_paragraph(
    "A. The Court Should Compel Further Responses Under CCP § 2030.300"
)
doc.add_paragraph(
    "A party propounding interrogatories may move for an order compelling a further response "
    "if the response is evasive or incomplete, or if an objection is without merit or too "
    "general. (Code Civ. Proc., § 2030.300, subd. (a).) The burden is on the objector to "
    "justify the objections. (Fairmont Ins. Co. v. Superior Court (2000) 22 Cal.4th 245, 255.) "
    "Here, Defendant has asserted the attorney-client privilege for factual observations of "
    "maintenance staff, which is legally unsupported."
)
doc.add_paragraph("")
doc.add_paragraph(
    "B. Boilerplate Objections Are Improper"
)
doc.add_paragraph(
    "General objections such as 'overly broad' and 'unduly burdensome' are improper without "
    "a specific showing of the burden. (West Pico Furniture Co. v. Superior Court (1961) "
    "56 Cal.2d 407, 417.) Defendant merely states that reviewing maintenance logs would be "
    "burdensome, but provides no declaration attesting to the volume of such records."
)
doc.add_paragraph("")

# CONCLUSION
p = doc.add_paragraph("CONCLUSION")
p.runs[0].bold = True
doc.add_paragraph(
    "For the foregoing reasons, Plaintiff respectfully requests that this Court grant the "
    "motion and order Defendant to provide full, verified responses without objection within 10 days."
)
doc.add_paragraph("")

# DECLARATION
p = doc.add_paragraph("DECLARATION OF MARIA SANTOS")
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.runs[0].bold = True
doc.add_paragraph(
    "I, Maria Santos, declare as follows:"
)
doc.add_paragraph(
    "1. I am an attorney at law duly licensed to practice before all courts of the State of "
    "California and am counsel of record for Plaintiff."
)
doc.add_paragraph(
    "2. On January 4, 2024, I sent a meet-and-confer letter to opposing counsel detailing the "
    "deficiencies in their responses. A true and correct copy is attached hereto as Exhibit A."
)
doc.add_paragraph(
    "I declare under penalty of perjury under the laws of the State of California that the "
    "foregoing is true and correct."
)
doc.add_paragraph("")
doc.add_paragraph("Maria Santos")

doc.save("/home/ga/Documents/motion_draft.docx")
print("Draft created successfully.")
PYEOF

# Fix permissions
sudo chown ga:ga /home/ga/Documents/motion_draft.docx
sudo chmod 666 /home/ga/Documents/motion_draft.docx

# Launch LibreOffice Writer with the draft
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/motion_draft.docx > /tmp/writer_task.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
if wait_for_window "LibreOffice Writer" 60; then
    echo "Writer window detected."
else
    # Fallback check for document name
    wait_for_window "motion_draft" 10 || echo "Warning: Window detection timed out"
fi

# Maximize the window
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid..."
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
    focus_window "$wid"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="