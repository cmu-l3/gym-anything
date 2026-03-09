#!/bin/bash
set -e
echo "=== Setting up Magazine Article Typesetting Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create document directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate the content using python-docx first (easier content generation), 
# then convert to ODT to ensure we start with a clean native format state.
echo "Generating article content..."
python3 << 'PYEOF'
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()

# Title
title = doc.add_paragraph("The Micro-Forest Revolution")
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = title.runs[0]
run.bold = True
run.font.size = Pt(24)
run.font.name = "Liberation Sans"

# Author
author = doc.add_paragraph("By Elena Rostova, Urban Ecology Correspondent")
author.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = author.runs[0]
run.italic = True
run.font.size = Pt(12)
run.font.name = "Liberation Sans"

doc.add_paragraph("") # Spacer

# Body Text (Realistic content about Miyawaki forests)
body_text = [
    "In the heart of dense concrete jungles, a quiet revolution is taking root. Small, hyper-dense patches of native woodland, known as Miyawaki forests, are springing up in schoolyards, roadside verges, and abandoned lots across the globe. Named after the Japanese botanist Akira Miyawaki, who developed the method in the 1970s, these micro-forests are challenging conventional wisdom about how long it takes to restore a functional ecosystem.",
    "Unlike traditional forestry, which typically plants distinct rows of timber trees, the Miyawaki method involves planting a diverse mix of native species close together—often three to four saplings per square meter. This density triggers a race for sunlight, encouraging the trees to grow upwards rather than outwards. The result is a forest that grows ten times faster, becomes thirty times denser, and contains one hundred times more biodiversity than a conventional plantation.",
    "For city planners and environmentalists, the appeal is obvious. Urban heat islands—metropolitan areas that are significantly warmer than their rural surroundings—pose a major health risk. These tiny ecosystems can lower urban temperatures by up to 4 degrees. Furthermore, their complex root systems act like a sponge, absorbing rainwater and reducing the risk of flash flooding, a growing concern in the era of climate change.",
    "Critics initially argued that the method was too expensive due to the soil preparation required. The ground must be excavated and enriched with organic compost and nutrients before planting can begin. However, proponents argue that the long-term benefits far outweigh the initial costs. Once established, usually within two to three years, a Miyawaki forest requires no watering or maintenance, becoming a self-sustaining ecosystem.",
    "In Paris, the method has been adopted to create 'cooling islands' ahead of the 2024 Olympics. In India, citizen groups have planted millions of trees using this technique to combat air pollution. The trend has even reached corporate campuses in Silicon Valley, where tech giants are using micro-forests to meet sustainability goals and provide mental health respites for employees.",
    "\"It changes the way we think about nature in the city,\" says Dr. Marcus Thorne, a landscape architect specializing in regenerative design. \"We used to think we needed acres of parkland to make a difference. Now we know that a tennis-court-sized patch of land can become a carbon sink and a haven for pollinators.\"",
    "As urbanization continues to accelerate, the integration of nature into the built environment is no longer a luxury but a necessity. The micro-forest revolution suggests that the solution to our ecological problems might not be finding more space, but making better use of the space we have."
]

for para in body_text:
    p = doc.add_paragraph(para)
    p.paragraph_format.space_after = Pt(12)
    run = p.runs[0]
    run.font.name = "Liberation Serif"
    run.font.size = Pt(11)

doc.save("/tmp/temp_draft.docx")
PYEOF

# Convert to ODT (LibreOffice native format)
echo "Converting to ODT..."
writer-headless convert-odt /tmp/temp_draft.docx
mv /tmp/temp_draft.odt /home/ga/Documents/article_draft.odt
rm /tmp/temp_draft.docx

# Set permissions
chown ga:ga /home/ga/Documents/article_draft.odt
chmod 666 /home/ga/Documents/article_draft.odt

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/article_draft.odt > /tmp/writer.log 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "article_draft" 20

# Get window ID and maximize
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    
    # Dismiss any initial dialogs (like "Tip of the Day")
    sleep 2
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="