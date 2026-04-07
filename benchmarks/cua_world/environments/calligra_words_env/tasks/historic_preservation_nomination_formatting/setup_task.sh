#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Historic Preservation Nomination Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time

kill_calligra_processes

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

rm -f /home/ga/Documents/riverside_nrhp_nomination.odt
rm -f /home/ga/Desktop/nps_formatting_guidelines.txt
rm -f /home/ga/Desktop/historic_boundary_map.jpg

echo "Downloading real map data..."
# Download a public domain map of Riverside County from Wikimedia Commons
wget -qO /home/ga/Desktop/historic_boundary_map.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2f/Map_of_Riverside_County_California.png/800px-Map_of_Riverside_County_California.png" || true

# Fallback if download fails (generate a basic valid image using python/PIL)
if [ ! -f /home/ga/Desktop/historic_boundary_map.jpg ]; then
    echo "Download failed, generating fallback image..."
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 600), color=(200, 220, 200))
d = ImageDraw.Draw(img)
d.rectangle([(100, 100), (700, 500)], outline=(0, 0, 0), width=5)
d.text((350, 300), 'Historic District Boundary Map', fill=(0, 0, 0))
img.save('/home/ga/Desktop/historic_boundary_map.jpg')
"
fi
chown ga:ga /home/ga/Desktop/historic_boundary_map.jpg

echo "Creating NPS guidelines document..."
cat > /home/ga/Desktop/nps_formatting_guidelines.txt << 'EOF'
NATIONAL PARK SERVICE - NRHP NOMINATION FORMATTING GUIDELINES

1. PAGE LAYOUT:
   - Left Margin: 1.5 inches (Required for archival binding/punching)
   - Right Margin: 1.0 inch
   - Top/Bottom Margins: 1.0 inch

2. HEADINGS:
   - Form Title: Centered, Bold
   - Main Sections (e.g., SECTION 7, SECTION 8): Use "Heading 1" style
   - Subsections (e.g., Historical Context): Use "Heading 2" style

3. TEXT FORMATTING:
   - Body Text (Sections 7 & 8 narrative): Must be Double-Spaced to allow for SHPO reviewer annotations.
   - Other sections may remain single-spaced.

4. STRUCTURE:
   - Insert a Page Break immediately before SECTION 8 (Statement of Significance must begin on a new page).

5. MEDIA:
   - Attach boundary map images within the document at the end of SECTION 10.
EOF
chown ga:ga /home/ga/Desktop/nps_formatting_guidelines.txt

echo "Generating raw unformatted nomination narrative..."
# ------------------------------------------------------------------
# Create the unformatted NRHP document using odfpy
# ALL content is plain P elements — no heading styles, no bold, etc.
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# ── Title elements ──
add_paragraph("NATIONAL REGISTER OF HISTORIC PLACES NOMINATION FORM")
add_paragraph("Riverside Industrial Historic District")
add_paragraph("")

# ── SECTION 7 ──
add_paragraph("SECTION 7. DESCRIPTION")
add_paragraph("Architectural Development")
add_paragraph(
    "The Riverside Industrial Historic District comprises a contiguous collection of "
    "thirty-two contributing resources that characterize the industrial development "
    "of the region between 1910 and 1945. The buildings are primarily utilitarian "
    "in design, featuring structural brick masonry, steel-sash windows, and sawtooth "
    "roof monitors that maximized natural light for manufacturing activities prior to "
    "the widespread adoption of fluorescent lighting. Key architectural styles include "
    "early 20th-century Commercial Brick and simplified Art Deco detailing on primary "
    "administrative facades."
)
add_paragraph("Current Condition")
add_paragraph(
    "The buildings remain in their original locations and retain a high degree of "
    "architectural integrity. While some fenestration has been altered or filled in "
    "with concrete block over the decades, the historic massing, spatial relationships, "
    "and materials remain clearly readable. The streetscape retains its historic "
    "granite curbing and embedded rail spurs that historically connected the factories "
    "to the main regional freight line."
)
add_paragraph("")

# ── SECTION 8 ──
add_paragraph("SECTION 8. STATEMENT OF SIGNIFICANCE")
add_paragraph("Period of Significance")
add_paragraph(
    "The period of significance spans from 1910, marking the construction of the "
    "first heavy manufacturing facility (the Apex Valve Foundry), to 1945, which "
    "represents the end of the district's rapid wartime expansion and peak "
    "production capacity. This period captures the primary era of the district's "
    "contribution to regional industry."
)
add_paragraph("Historical Context")
add_paragraph(
    "During the early 20th century, the expansion of the regional rail network "
    "transformed this previously agricultural area into a dense manufacturing center. "
    "The availability of cheap hydroelectric power and proximity to transportation "
    "corridors attracted heavy industries, including foundries, textile mills, and "
    "machine tool fabricators. The workforce was largely drawn from adjacent immigrant "
    "neighborhoods, establishing a deep socioeconomic link between the factories "
    "and the surrounding community."
)
add_paragraph("Industrial Impact")
add_paragraph(
    "The district served as a major manufacturing hub during both World War I and "
    "World War II, shifting production from domestic goods to military ordnance and "
    "vehicle components. The surviving physical plant of the district provides a "
    "highly intact visual record of early 20th-century industrial engineering and "
    "factory layout, meeting Criterion A for its association with industrial history "
    "and Criterion C for its embodiment of distinctive industrial architectural types."
)
add_paragraph("")

# ── SECTION 9 ──
add_paragraph("SECTION 9. MAJOR BIBLIOGRAPHICAL REFERENCES")
add_paragraph(
    "1. Riverside Historical Society Archives, Industrial Survey Collection, 1978."
)
add_paragraph(
    "2. Sanborn Fire Insurance Maps, Riverside Editions: 1912, 1925, 1941, 1955."
)
add_paragraph(
    "3. Department of the Interior, National Park Service, National Register Bulletin "
    "16A: How to Complete the National Register Registration Form, 1997."
)
add_paragraph("")

# ── SECTION 10 ──
add_paragraph("SECTION 10. GEOGRAPHICAL DATA")
add_paragraph("Acreage of Property: 14.5 acres")
add_paragraph("UTM References: Zone 11, Easting 465200, Northing 3758400")
add_paragraph(
    "Verbal Boundary Description: The district is bounded by the Southern Pacific "
    "railroad right-of-way to the north, 4th Street to the east, Industrial Boulevard "
    "to the south, and the Riverside Canal to the west, as indicated on the attached "
    "boundary map."
)
add_paragraph("")

doc.save("/home/ga/Documents/riverside_nrhp_nomination.odt")
PYEOF

chown ga:ga /home/ga/Documents/riverside_nrhp_nomination.odt

# Launch Calligra Words
echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/riverside_nrhp_nomination.odt"
sleep 5

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/calligra_historic_nomination_pre_task.png

echo "=== Task Setup Complete ==="