#!/bin/bash
set -e
echo "=== Setting up Create Custom Slide Shows task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure presentation directory exists
PRES_DIR="/home/ga/Documents/Presentations"
mkdir -p "$PRES_DIR"

# Kill any existing LibreOffice instances
pkill -f soffice 2>/dev/null || true
sleep 2

# Generate the 8-slide presentation using odfpy
# We embed the python script to ensure it runs within the container environment
cat > /tmp/create_presentation.py << 'PYEOF'
#!/usr/bin/env python3
"""Create an 8-slide ODP presentation about renewable energy strategy."""

import sys
try:
    from odf.opendocument import OpenDocumentPresentation
    from odf import draw, text, style, presentation
    from odf.style import Style, MasterPage, PageLayout, PageLayoutProperties, GraphicProperties, ParagraphProperties, TextProperties
    from odf.text import P, Span
except ImportError:
    print("Error: odfpy not installed")
    sys.exit(1)

output_path = sys.argv[1]

doc = OpenDocumentPresentation()

# Page layout
pagelayout = PageLayout(name="AL1")
doc.automaticstyles.addElement(pagelayout)
pagelayout.addElement(PageLayoutProperties(
    margin="0cm",
    pagewidth="28cm",
    pageheight="21cm",
    printorientation="landscape"
))

# Master page
masterpage = MasterPage(name="Default", pagelayoutname=pagelayout)
doc.masterstyles.addElement(masterpage)

# Title style
titlestyle = Style(name="TitleStyle", family="graphic")
titlestyle.addElement(GraphicProperties(stroke="none", fill="none"))
titlestyle.addElement(ParagraphProperties(textalign="center"))
titlestyle.addElement(TextProperties(fontsize="32pt", fontweight="bold", color="#1a3c6e"))
doc.automaticstyles.addElement(titlestyle)

# Body style
bodystyle = Style(name="BodyStyle", family="graphic")
bodystyle.addElement(GraphicProperties(stroke="none", fill="none"))
bodystyle.addElement(ParagraphProperties(textalign="start"))
bodystyle.addElement(TextProperties(fontsize="18pt", color="#333333"))
doc.automaticstyles.addElement(bodystyle)

# Slide content with real-world data
slides = [
    {
        "name": "page1",
        "title": "Renewable Energy Strategy 2025",
        "bullets": [
            "Global renewable capacity reached 3,870 GW in 2023 (IRENA)",
            "Company commitment: carbon neutrality by 2030",
            "Total planned investment: $240M over 5 years",
            "Aligns with Science Based Targets initiative (SBTi)"
        ]
    },
    {
        "name": "page2",
        "title": "Current Energy Portfolio Analysis",
        "bullets": [
            "Natural gas: 45% of total energy consumption (baseline 2023)",
            "Grid electricity: 38% - 12% from renewable sources",
            "On-site diesel generation: 11% at 3 manufacturing facilities",
            "Existing solar PV: 6% - 18 MW installed across 4 sites",
            "Scope 1 & 2 emissions: 142,000 tCO2e annually"
        ]
    },
    {
        "name": "page3",
        "title": "Market Trends and Opportunities",
        "bullets": [
            "Solar PV costs declined 89% since 2010 (IRENA 2024)",
            "Global corporate PPA volume exceeded 46 GW in 2023",
            "EU Carbon Border Adjustment Mechanism effective 2026",
            "Battery storage costs dropped below $140/kWh (BloombergNEF)",
            "Green hydrogen production scaling - $2.50/kg target by 2030"
        ]
    },
    {
        "name": "page4",
        "title": "Solar and Wind Implementation Plan",
        "bullets": [
            "Phase 1 (2025): 35 MW rooftop solar across 6 facilities",
            "Phase 2 (2026): 50 MW ground-mount solar at HQ campus",
            "Phase 3 (2027): 20 MW onshore wind PPA - 15-year term",
            "EPC contractor shortlist: 3 vendors, RFP closing Q1 2025",
            "Grid interconnection studies completed for all priority sites"
        ]
    },
    {
        "name": "page5",
        "title": "Financial Impact and ROI Projections",
        "bullets": [
            "Projected annual energy cost savings: $18.5M by 2028",
            "Payback period: 6.2 years (LCOE basis, unsubsidized)",
            "With IRA tax credits (ITC 30%): payback reduced to 4.1 years",
            "NPV at 8% discount rate: $47.3M over 20-year asset life",
            "Carbon credit revenue potential: $3.2M annually at $45/tCO2"
        ]
    },
    {
        "name": "page6",
        "title": "Environmental Compliance Framework",
        "bullets": [
            "ISO 14001:2015 certification maintained across all sites",
            "NEPA environmental impact assessment complete for solar sites",
            "Avian mortality risk assessment for wind projects (USFWS guidelines)",
            "Stormwater management plans updated for ground-mount arrays",
            "Decommissioning bond requirements: $2.1M total across projects"
        ]
    },
    {
        "name": "page7",
        "title": "Technology Integration Roadmap",
        "bullets": [
            "SCADA system upgrade: real-time monitoring of all DER assets",
            "Battery energy storage: 15 MWh at 3 critical facilities",
            "EV charging infrastructure: 200 Level 2 + 40 DC fast chargers",
            "Building management system integration - OpenADR 2.0 demand response",
            "Digital twin modeling for predictive maintenance (2026 pilot)"
        ]
    },
    {
        "name": "page8",
        "title": "Summary and Next Steps",
        "bullets": [
            "Board approval requested for Phase 1 ($62M capital allocation)",
            "Technical review committee to finalize EPC vendor selection by March",
            "Sustainability report publication: Q2 2025 (GRI Standards)",
            "Quarterly progress reviews with executive steering committee",
            "First renewable generation targeted: September 2025"
        ]
    }
]

for slide_data in slides:
    page = draw.Page(stylename=style.Style(name="dp1", family="drawing-page"),
                     name=slide_data["name"],
                     masterpagename=masterpage)
    doc.presentation.addElement(page)

    # Title frame
    titleframe = draw.Frame(stylename=titlestyle, width="24cm", height="3cm", x="2cm", y="1cm")
    page.addElement(titleframe)
    textbox = draw.TextBox()
    titleframe.addElement(textbox)
    p = P()
    p.addText(slide_data["title"])
    textbox.addElement(p)

    # Body frame with bullets
    bodyframe = draw.Frame(stylename=bodystyle, width="24cm", height="14cm", x="2cm", y="4.5cm")
    page.addElement(bodyframe)
    bodytextbox = draw.TextBox()
    bodyframe.addElement(bodytextbox)
    for bullet in slide_data["bullets"]:
        bp = P()
        bp.addText("- " + bullet)
        bodytextbox.addElement(bp)

doc.save(output_path)
print(f"Presentation saved to {output_path}")
PYEOF

echo "Generating presentation file..."
python3 /tmp/create_presentation.py "$PRES_DIR/renewable_energy_strategy.odp"
chown ga:ga "$PRES_DIR/renewable_energy_strategy.odp"

# Record initial file hash for anti-gaming
md5sum "$PRES_DIR/renewable_energy_strategy.odp" > /tmp/initial_file_hash.txt

# Launch LibreOffice Impress with the presentation
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress '$PRES_DIR/renewable_energy_strategy.odp' > /tmp/impress.log 2>&1 &"
sleep 5

# Wait for Impress window
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "impress\|renewable"; then
        echo "LibreOffice Impress window detected"
        break
    fi
    sleep 1
done

# Maximize and focus window
sleep 2
DISPLAY=:1 wmctrl -r "LibreOffice Impress" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Fallback to active if name mismatch
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs (like Tip of the Day)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="