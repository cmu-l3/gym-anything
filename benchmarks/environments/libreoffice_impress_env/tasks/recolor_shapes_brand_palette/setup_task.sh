#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Recolor Shapes Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Generate the initial presentation programmatically
# We use Python/odfpy to ensure a clean, known initial state with specific IDs/Styles if possible
cat > /tmp/create_esg_report.py << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, TextProperties, GraphicProperties, ParagraphProperties, DrawingPageProperties
from odf.draw import Page, Frame, TextBox, Rect, Ellipse
from odf.text import P
from odf.base import Double

def create_presentation():
    doc = OpenDocumentPresentation()
    
    # Define styles
    # Default gray shape style
    gray_style = Style(name="GrayShape", family="graphic")
    gray_style.addElement(GraphicProperties(fill="solid", fillcolor="#c0c0c0", stroke="none"))
    doc.styles.addElement(gray_style)

    # Title style (Black text)
    title_style = Style(name="TitleText", family="presentation")
    title_style.addElement(TextProperties(color="#000000", fontname="Liberation Sans", fontsize="44pt", fontweight="bold"))
    title_style.addElement(ParagraphProperties(textalign="center"))
    doc.styles.addElement(title_style)

    # Content data
    slides_content = [
        ("Carbon Emissions Overview", ["Scope 1 Emissions: 12,450 tCO2e", "Scope 2 Emissions: 4,200 tCO2e", "Target: Net Zero by 2040"]),
        ("Water Stewardship Metrics", ["Total Withdrawal: 5.4 Megaliters", "Recycling Rate: 45%", "Watershed Risk Assessment: Low"]),
        ("Workforce Diversity Index", ["Gender Balance: 48% Female", "Leadership Roles: 35% Diverse", "Inclusive Hiring Policy Implemented"]),
        ("Governance Risk Assessment", ["Board Independence: 80%", "Audit Committee: Fully Independent", "Whistleblower Policy: Active"])
    ]

    for i, (title_text, bullets) in enumerate(slides_content):
        page = Page(name=f"Slide{i+1}")
        doc.presentation.addElement(page)

        # 1. Title Frame
        title_frame = Frame(width="25cm", height="3cm", x="1.5cm", y="1cm", presentationclass="title")
        title_textbox = TextBox()
        title_frame.addElement(title_textbox)
        title_textbox.addElement(P(text=title_text, stylename=title_style))
        page.addElement(title_frame)

        # 2. Content Frame (Body text)
        body_frame = Frame(width="25cm", height="8cm", x="1.5cm", y="4.5cm", presentationclass="outline")
        body_textbox = TextBox()
        body_frame.addElement(body_textbox)
        for bullet in bullets:
            body_textbox.addElement(P(text=bullet))
        page.addElement(body_frame)

        # 3. Shapes (2 Rectangles, 1 Ellipse) - using default gray
        # Rect 1
        r1 = Rect(width="4cm", height="3cm", x="2cm", y="13cm", stylename=gray_style)
        page.addElement(r1)

        # Rect 2
        r2 = Rect(width="4cm", height="3cm", x="7cm", y="13cm", stylename=gray_style)
        page.addElement(r2)

        # Ellipse 1 (KPI Indicator)
        e1 = Ellipse(width="3cm", height="3cm", x="13cm", y="13cm", stylename=gray_style)
        page.addElement(e1)

    output_path = "/home/ga/Documents/Presentations/esg_report.odp"
    doc.save(output_path)
    print(f"Created {output_path}")

if __name__ == "__main__":
    create_presentation()
PYEOF

echo "Generating ODP file..."
python3 /tmp/create_esg_report.py
sudo chown ga:ga /home/ga/Documents/Presentations/esg_report.odp

# Record initial hash
md5sum /home/ga/Documents/Presentations/esg_report.odp > /tmp/initial_file_hash.txt

# Launch Impress
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/esg_report.odp > /tmp/impress.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
if ! wait_for_window "esg_report" 60; then
    echo "WARNING: Window 'esg_report' not found, checking generic..."
    wait_for_window "LibreOffice Impress" 10
fi

# Maximize and focus
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any potential recovery dialogs (ESC twice usually works)
sleep 2
safe_xdotool ga :1 key Escape
sleep 0.5
safe_xdotool ga :1 key Escape

# Final focus
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Recolor shapes and text in /home/ga/Documents/Presentations/esg_report.odp"
echo "Target Colors:"
echo "  - Rectangles: #2E7D32 (Forest Green)"
echo "  - Ellipses:   #FF8F00 (Amber)"
echo "  - Titles:     #0D47A1 (Dark Blue)"