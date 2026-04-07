#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Transit Plan Accessibility Remediation Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop
kill_calligra_processes
rm -f /home/ga/Documents/draft_transit_plan.odt

# ------------------------------------------------------------------
# Create the "fake" visually-formatted draft plan using odfpy.
# All elements are standard paragraphs. Headings are simulated with
# bold text. Lists are simulated with manual hyphens. Tables are
# simulated with tab characters.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P, Tab
import os

doc = OpenDocumentText()

# Fake H1 (Bold, Large text, but semantically just a paragraph)
fake_h1 = Style(name="FakeH1", family="paragraph")
fake_h1.addElement(TextProperties(fontweight="bold", fontsize="18pt"))
fake_h1.addElement(ParagraphProperties(margintop="0.5cm", marginbottom="0.2cm"))
doc.automaticstyles.addElement(fake_h1)

# Fake H2 (Bold, Medium text, but semantically just a paragraph)
fake_h2 = Style(name="FakeH2", family="paragraph")
fake_h2.addElement(TextProperties(fontweight="bold", fontsize="14pt"))
fake_h2.addElement(ParagraphProperties(margintop="0.4cm", marginbottom="0.1cm"))
doc.automaticstyles.addElement(fake_h2)

# Body Text
body_style = Style(name="Body", family="paragraph")
body_style.addElement(TextProperties(fontsize="12pt"))
doc.automaticstyles.addElement(body_style)

def add_fake_h1(text):
    doc.text.addElement(P(stylename=fake_h1, text=text))

def add_fake_h2(text):
    doc.text.addElement(P(stylename=fake_h2, text=text))

def add_p(text):
    doc.text.addElement(P(stylename=body_style, text=text))

def add_tab_row(col1, col2, col3):
    p = P(stylename=body_style)
    p.addText(col1)
    p.addElement(Tab())
    p.addText(col2)
    p.addElement(Tab())
    p.addText(col3)
    doc.text.addElement(p)

add_fake_h1("Draft Active Transportation Plan")
add_p("Prepared for the Regional Transit Agency.")
add_p("")
add_fake_h1("Executive Summary")
add_p("This draft plan outlines the active transportation improvements proposed for the next five years. Our goal is to increase accessibility and safety for all non-motorized users.")
add_p("")
add_fake_h1("Existing Conditions")
add_p("Currently, the city features a disjointed network of bike lanes and sidewalks. Pedestrian outfalls are lacking in the downtown corridor, and Vision Zero goals are not being met.")
add_p("")
add_fake_h2("Proposed Bicycle Facilities")
add_p("The following facility types are proposed to complete the network:")
add_p("- Protected Bike Lanes")
add_p("- Buffered Bike Lanes")
add_p("- Bicycle Boulevards")
add_p("- Shared Use Paths")
add_p("")
add_fake_h2("Project Funding Summary")
add_p("The table below details the estimated costs and funding sources for the major network expansions:")
add_tab_row("Project Area", "Estimated Cost", "Funding Source")
add_tab_row("Downtown Network", "$4.2M", "CMAQ")
add_tab_row("Riverfront Path", "$8.5M", "State Grant")
add_tab_row("University Connector", "$2.1M", "Local Measure")
add_p("")
add_fake_h1("Implementation Timeline")
add_p("Projects will be phased over the next five fiscal years, prioritizing high-injury corridors first.")

doc_path = "/home/ga/Documents/draft_transit_plan.odt"
doc.save(doc_path)
os.chown(doc_path, 1000, 1000) # ga:ga
PYEOF

# Create the instructions file on the Desktop
cat > /home/ga/Desktop/remediation_requirements.txt << 'EOF'
REMEDIATION REQUIREMENTS (SECTION 508 COMPLIANCE)

The attached document "draft_transit_plan.odt" contains accessibility violations. 
Visual formatting has been used instead of structural semantics.

Please fix the following:
1. HEADINGS: Convert all bolded section titles to proper 'Heading 1' and 'Heading 2' styles.
2. LISTS: Convert the hyphenated list of facilities to a true semantic 'Bulleted List' and delete the manual hyphens.
3. TABLES: Convert the tab-separated funding data into a proper semantic Table.
4. NAVIGATION: Generate and insert a 'Table of Contents' at the top of the document.
EOF
chown ga:ga /home/ga/Desktop/remediation_requirements.txt

# Launch Calligra Words
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords /home/ga/Documents/draft_transit_plan.odt >/tmp/calligra_task.log 2>&1 < /dev/null &"

# Wait for Calligra to appear
echo "Waiting for Calligra Words..."
for i in {1..30}; do
    if wmctrl -l | grep -qi "Calligra Words"; then
        break
    fi
    sleep 1
done
sleep 2

# Maximize the window
WID=$(wmctrl -l | grep -i "Calligra Words" | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    wmctrl -ia "$WID" 2>/dev/null || true
fi

# Dismiss any startup tooltips/dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga
echo "=== Setup complete ==="