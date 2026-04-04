#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Merge Presentations Task ==="

# 1. Setup Directories and Anti-Gaming
# -------------------------------------
USER_HOME="/home/ga"
PRES_DIR="$USER_HOME/Documents/Presentations"
mkdir -p "$PRES_DIR"
chown ga:ga "$PRES_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f "$PRES_DIR/Executive_Briefing.odp"
rm -f "$PRES_DIR/BIA_Findings.odp"
rm -f "$PRES_DIR/Risk_Assessment.odp"

# 2. Generate Source Presentations
# --------------------------------
# We use Python within the container (where odfpy is installed) to generate valid ODP files
echo "Generating source presentation files..."

cat > /tmp/gen_pres.py << 'PYEOF'
import sys
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties
from odf.text import P
from odf.draw import Page, Frame, TextBox, Image

def create_slide(doc, title_text, bullets):
    page = Page(name=f"Slide{len(doc.getElementsByType(Page))+1}")
    doc.presentation.addElement(page)

    # Title Frame
    title_frame = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm")
    page.addElement(title_frame)
    title_textbox = TextBox()
    title_frame.addElement(title_textbox)
    title_p = P(text=title_text)
    title_textbox.addElement(title_p)

    # Content Frame
    content_frame = Frame(width="25cm", height="12cm", x="1.5cm", y="5cm")
    page.addElement(content_frame)
    content_textbox = TextBox()
    content_frame.addElement(content_textbox)
    
    for bullet in bullets:
        p = P(text=f"• {bullet}")
        content_textbox.addElement(p)

# --- Create BIA_Findings.odp (4 slides) ---
doc1 = OpenDocumentPresentation()
create_slide(doc1, "Business Impact Analysis: Q4 2024 Review", 
             ["Scope: 12 departments, 47 business processes evaluated", 
              "Methodology aligned with ISO 22301:2019 and NIST SP 800-34", 
              "Assessment period: September through November 2024"])
create_slide(doc1, "Critical Business Functions", 
             ["Tier 1: Order processing, payment gateway, customer support hotline", 
              "Tier 2: Payroll processing, IT helpdesk, vendor management portal", 
              "Tier 3: Internal reporting, employee training, facilities scheduling", 
              "23 functions classified as mission-critical"])
create_slide(doc1, "Recovery Time Objectives", 
             ["Tier 1 systems: RTO 4 hours, RPO 1 hour", 
              "Tier 2 systems: RTO 24 hours, RPO 4 hours", 
              "Current gap: 3 of 8 Tier 1 systems exceed target RTO", 
              "Recommended investment: Redundant failover"])
create_slide(doc1, "Resource Dependencies", 
             ["AWS us-east-1 hosts 78% of production workloads", 
              "Vendor concentration: Top 3 vendors support 60% of critical functions", 
              "Key person dependencies identified in 4 departments", 
              "Backup power capacity limited to 6 hours"])
doc1.save("/home/ga/Documents/Presentations/BIA_Findings.odp")

# --- Create Risk_Assessment.odp (3 slides) ---
doc2 = OpenDocumentPresentation()
create_slide(doc2, "Enterprise Risk Assessment Summary", 
             ["47 risks identified across 8 categories per ISO 22301 framework", 
              "Risk scoring methodology: Likelihood (1-5) x Impact (1-5)", 
              "12 risks rated Critical or High requiring immediate mitigation", 
              "Assessment conducted by cross-functional team"])
create_slide(doc2, "Threat Landscape Analysis", 
             ["Ransomware: 340% increase in sector-specific attacks", 
              "Supply chain disruption: Average 23-day recovery", 
              "Natural disasters: Flood zone reclassification", 
              "Insider threats: 3 incidents detected in prior 12 months"])
create_slide(doc2, "Mitigation Strategies and Recommendations", 
             ["Priority 1: Deploy multi-region cloud failover ($280K)", 
              "Priority 2: Establish secondary vendor contracts", 
              "Priority 3: Implement quarterly tabletop exercises", 
              "Total recommended budget: $1.2M"])
doc2.save("/home/ga/Documents/Presentations/Risk_Assessment.odp")
PYEOF

# Run generator as ga user
su - ga -c "python3 /tmp/gen_pres.py"
rm /tmp/gen_pres.py

echo "Created BIA_Findings.odp and Risk_Assessment.odp"

# 3. Launch Application
# ---------------------
# Ensure no lingering instances
pkill -f "soffice" || true
pkill -f "libreoffice" || true
sleep 1

echo "Launching LibreOffice Impress with BIA_Findings.odp..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$PRES_DIR/BIA_Findings.odp' > /tmp/impress.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Impress" 60

# Maximize
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    echo "Maximizing window $wid"
    DISPLAY=:1 wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
    focus_window "$wid"
else
    echo "WARNING: Could not find Impress window ID"
fi

# Dismiss any recovery dialogs if they appear (defensive)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="