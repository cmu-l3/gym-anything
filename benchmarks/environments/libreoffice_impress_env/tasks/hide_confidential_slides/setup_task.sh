#!/bin/bash
set -e
echo "=== Setting up hide_confidential_slides task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

PRES_DIR="/home/ga/Documents/Presentations"
PRES_FILE="$PRES_DIR/quarterly_review.pptx"

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Create presentations directory
sudo -u ga mkdir -p "$PRES_DIR"

# Generate the 8-slide quarterly review presentation using python-pptx
cat > /tmp/create_presentation.py << 'PYEOF'
#!/usr/bin/env python3
"""Create a realistic 8-slide quarterly business review presentation."""
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
import sys

prs = Presentation()
# Widescreen
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

# Layout indices (standard template)
TITLE_LAYOUT = 0
CONTENT_LAYOUT = 1

slides_content = [
    {
        "title": "Q3 2024 Quarterly Business Review",
        "subtitle": "TechVision Solutions Inc.\nPrepared for Client Partnership Meeting\nOctober 2024",
        "layout": TITLE_LAYOUT,
    },
    {
        "title": "Meeting Agenda",
        "bullets": [
            "Revenue performance and growth trends",
            "Customer satisfaction metrics and NPS results",
            "Product roadmap highlights for Q4",
            "Partnership expansion opportunities",
            "Q4 targets and action items",
        ],
        "layout": CONTENT_LAYOUT,
    },
    {
        "title": "[INTERNAL] Cost Structure Analysis",
        "bullets": [
            "COGS decreased 4.2% QoQ due to supply chain optimization",
            "Engineering headcount: 847 FTEs at avg $142K loaded cost",
            "Cloud infrastructure spend: $3.8M/month (AWS + GCP)",
            "Customer acquisition cost (CAC): $1,247 per enterprise seat",
            "Gross margin target: 72% (actual: 69.3% — gap analysis pending)",
            "DO NOT SHARE — Internal financial data only",
        ],
        "layout": CONTENT_LAYOUT,
    },
    {
        "title": "Revenue Performance",
        "bullets": [
            "Q3 total revenue: $48.7M (up 18% YoY)",
            "Enterprise segment: $31.2M (64% of total)",
            "SMB segment: $12.4M (25% of total)",
            "Services & support: $5.1M (11% of total)",
            "Net revenue retention rate: 118%",
            "12 new enterprise logos acquired in Q3",
        ],
        "layout": CONTENT_LAYOUT,
    },
    {
        "title": "[INTERNAL] Profit Margins by Product",
        "bullets": [
            "Platform Core: 78% gross margin ($24.1M revenue)",
            "Analytics Suite: 64% gross margin ($11.3M revenue)",
            "Integration Hub: 81% gross margin ($8.2M revenue)",
            "Professional Services: 31% gross margin ($5.1M revenue)",
            "Blended operating margin: 14.7% (target: 18%)",
            "CONFIDENTIAL — Not for external distribution",
        ],
        "layout": CONTENT_LAYOUT,
    },
    {
        "title": "Customer Satisfaction Results",
        "bullets": [
            "Net Promoter Score (NPS): 62 (industry avg: 41)",
            "Customer satisfaction (CSAT): 4.3/5.0",
            "Support ticket resolution: 94% within SLA",
            "Average first response time: 2.1 hours",
            "Feature request fulfillment rate: 67%",
            "3 case studies published with client testimonials",
        ],
        "layout": CONTENT_LAYOUT,
    },
    {
        "title": "[INTERNAL] Competitive Pricing Analysis",
        "bullets": [
            "Competitor A (Acme Corp): $85/seat/month — 12% below our pricing",
            "Competitor B (DataFlow): $110/seat/month — 3% above our pricing",
            "Competitor C (CloudBridge): $72/seat/month — aggressive discounting",
            "Our average selling price: $97/seat/month",
            "Win rate vs Competitor A: 58% (down from 63% in Q2)",
            "STRICTLY CONFIDENTIAL — Competitive intelligence",
        ],
        "layout": CONTENT_LAYOUT,
    },
    {
        "title": "Q4 Outlook & Next Steps",
        "bullets": [
            "Q4 revenue target: $54.2M (11% QoQ growth)",
            "Product launch: Analytics Suite v3.0 (November)",
            "Expand APAC partnership channel",
            "3 enterprise POCs in pipeline (est. $4.8M ACV)",
            "Annual customer conference: TechVision Summit Dec 5-7",
            "Next QBR scheduled: January 15, 2025",
        ],
        "layout": CONTENT_LAYOUT,
    },
]

for i, content in enumerate(slides_content):
    layout_idx = content.get("layout", CONTENT_LAYOUT)
    try:
        slide_layout = prs.slide_layouts[layout_idx]
    except:
        slide_layout = prs.slide_layouts[0] # Fallback
        
    slide = prs.slides.add_slide(slide_layout)

    # Set title
    if slide.shapes.title:
        slide.shapes.title.text = content["title"]
        # Basic red color for INTERNAL titles
        if "[INTERNAL]" in content["title"]:
             pass # Color setting simplified for robustness

    # Set subtitle or bullets
    if "subtitle" in content:
        # Try to find subtitle placeholder
        for shape in slide.placeholders:
            if shape.placeholder_format.idx == 1:
                shape.text = content["subtitle"]
                break
    elif "bullets" in content:
        for shape in slide.placeholders:
            if shape.placeholder_format.idx == 1:
                tf = shape.text_frame
                tf.clear()
                for bullet in content["bullets"]:
                    p = tf.add_paragraph()
                    p.text = bullet

output_path = sys.argv[1]
prs.save(output_path)
print(f"Presentation saved to {output_path}")
PYEOF

echo "Generating presentation file..."
python3 /tmp/create_presentation.py "$PRES_FILE"
chown ga:ga "$PRES_FILE"

# Record initial file hash
md5sum "$PRES_FILE" | awk '{print $1}' > /tmp/initial_file_hash.txt

# Launch LibreOffice Impress with the file
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$PRES_FILE' > /tmp/impress.log 2>&1 &"

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "impress\|quarterly"; then
        echo "LibreOffice Impress window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
impress_id=$(get_impress_window_id)
if [ -n "$impress_id" ]; then
    focus_window "$impress_id"
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="