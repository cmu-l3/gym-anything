#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Accessibility Document Retrofit Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial document with accessibility issues
DOC_PATH="$WORKSPACE_DIR/community_resources_draft.docx"

cat > /tmp/create_inaccessible_doc.py << 'PYEOF'
#!/usr/bin/env python3
"""
Create a document with accessibility issues:
- Visual headings (bold, large) instead of proper heading styles
- Images with NO alt text
- No table of contents
"""
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH
from PIL import Image
import io
import sys

doc = Document()

# Title - properly formatted and centered
title_para = doc.add_paragraph()
title_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
title_run = title_para.add_run("COMMUNITY ACCESSIBILITY RESOURCE GUIDE")
title_run.font.size = Pt(18)
title_run.font.bold = True

doc.add_paragraph("")  # Empty line

# Section 1: Transportation Services
# THIS IS A VISUAL HEADING - bold and large, but NOT Heading 1 style
section1 = doc.add_paragraph()
section1_run = section1.add_run("Transportation Services")
section1_run.font.size = Pt(16)
section1_run.font.bold = True

doc.add_paragraph("Our city offers several accessible transportation options for residents with mobility challenges.")

# Add image 1 - wheelchair ramp (NO ALT TEXT)
img1 = Image.new('RGB', (400, 250), color=(135, 206, 250))  # Light blue
img1_bytes = io.BytesIO()
img1.save(img1_bytes, format='PNG')
img1_bytes.seek(0)
doc.add_picture(img1_bytes, width=Inches(2.5))

doc.add_paragraph("The Access Bus provides door-to-door service with wheelchair lifts.")

doc.add_paragraph("")  # Empty line

# Section 2: Communication Resources
# THIS IS A VISUAL HEADING - bold and large, but NOT Heading 1 style
section2 = doc.add_paragraph()
section2_run = section2.add_run("Communication Resources")
section2_run.font.size = Pt(16)
section2_run.font.bold = True

doc.add_paragraph("For residents who are deaf or hard of hearing, several services are available.")

doc.add_paragraph("")  # Empty line

# Subsection 2.1: TTY Services
# THIS IS A VISUAL SUB-HEADING - bold and medium size, but NOT Heading 2 style
subsection1 = doc.add_paragraph()
subsection1_run = subsection1.add_run("TTY Services")
subsection1_run.font.size = Pt(14)
subsection1_run.font.bold = True

doc.add_paragraph("The city maintains TTY phone lines for emergency and non-emergency calls.")

# Add image 2 - TTY device (NO ALT TEXT)
img2 = Image.new('RGB', (400, 250), color=(144, 238, 144))  # Light green
img2_bytes = io.BytesIO()
img2.save(img2_bytes, format='PNG')
img2_bytes.seek(0)
doc.add_picture(img2_bytes, width=Inches(2.5))

doc.add_paragraph("")  # Empty line

# Subsection 2.2: Video Relay Service
# THIS IS A VISUAL SUB-HEADING - bold and medium size, but NOT Heading 2 style
subsection2 = doc.add_paragraph()
subsection2_run = subsection2.add_run("Video Relay Service")
subsection2_run.font.size = Pt(14)
subsection2_run.font.bold = True

doc.add_paragraph("Free video relay interpretation is available through multiple providers.")

doc.add_paragraph("")  # Empty line

# Section 3: Service Animal Resources
# THIS IS A VISUAL HEADING - bold and large, but NOT Heading 1 style
section3 = doc.add_paragraph()
section3_run = section3.add_run("Service Animal Resources")
section3_run.font.size = Pt(16)
section3_run.font.bold = True

doc.add_paragraph("Information about service animal rights and training programs.")

# Add image 3 - service dog (NO ALT TEXT)
img3 = Image.new('RGB', (400, 250), color=(255, 255, 224))  # Light yellow
img3_bytes = io.BytesIO()
img3.save(img3_bytes, format='PNG')
img3_bytes.seek(0)
doc.add_picture(img3_bytes, width=Inches(2.5))

doc.add_paragraph("All businesses must allow service animals under the ADA.")

# Save document
doc.save(sys.argv[1])
print(f"✅ Inaccessible document created: {sys.argv[1]}")
print("   Issues: Visual headings (not styles), images without alt text, no TOC")
PYEOF

chmod +x /tmp/create_inaccessible_doc.py
python3 /tmp/create_inaccessible_doc.py "$DOC_PATH"
chown ga:ga "$DOC_PATH"

echo "✅ Document created at: $DOC_PATH"

# Launch ONLYOFFICE with the document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$DOC_PATH' > /tmp/onlyoffice_accessibility_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_accessibility_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Accessibility Document Retrofit Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You're a volunteer at 'Access for All Coalition' disability rights nonprofit."
echo "  A partner sent you this community resource guide, but it's completely"
echo "  inaccessible to screen reader users. Your supervisor needs it fixed TODAY"
echo "  to meet WCAG 2.1 Level AA standards before publication."
echo ""
echo "🔧 REQUIRED FIXES:"
echo ""
echo "1. Convert visual headings to proper Heading 1 style:"
echo "   - 'Transportation Services'"
echo "   - 'Communication Resources'"
echo "   - 'Service Animal Resources'"
echo ""
echo "2. Convert visual sub-headings to proper Heading 2 style:"
echo "   - 'TTY Services'"
echo "   - 'Video Relay Service'"
echo ""
echo "3. Add alt text to all 3 images:"
echo "   - Image 1 (blue): 'Accessible entrance ramp with handrails'"
echo "   - Image 2 (green): 'TTY telecommunication device for deaf users'"
echo "   - Image 3 (yellow): 'Service dog with accessibility vest'"
echo ""
echo "4. Insert a Table of Contents after the title"
echo ""
echo "5. Save as: community_resources_accessible.docx"
echo ""
echo "💡 HOW TO:"
echo "  - Apply heading style: Select text → Home tab → Styles → Heading 1/2"
echo "  - Add alt text: Right-click image → Edit Alt Text / Image Properties"
echo "  - Insert TOC: References tab → Table of Contents → Automatic Table"
echo "  - Save As: File → Save As (or Ctrl+Shift+S)"