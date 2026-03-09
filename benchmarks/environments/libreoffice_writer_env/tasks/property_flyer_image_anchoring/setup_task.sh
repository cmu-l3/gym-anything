#!/bin/bash
set -euo pipefail

echo "=== Setting up Real Estate Flyer Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create documents directory
mkdir -p /home/ga/Documents

# 1. Generate Placeholder Images (Logo, House, Signature)
# We use Python to generate simple colored rectangles with text to ensure we have valid image files
# without relying on external downloads that might fail.
echo "Generating asset images..."
python3 << 'PYEOF'
import os
from PIL import Image, ImageDraw, ImageFont

def create_image(filename, width, height, color, text):
    img = Image.new('RGB', (width, height), color)
    d = ImageDraw.Draw(img)
    # simple text centering (rough)
    try:
        # Use a default font
        d.text((10, height//2 - 10), text, fill=(255, 255, 255))
    except Exception:
        pass
    img.save(filename)

create_image("/tmp/logo.png", 100, 100, "darkblue", "LOGO")
create_image("/tmp/house.png", 400, 300, "forestgreen", "HOUSE PHOTO")
create_image("/tmp/signature.png", 200, 50, "black", "Signature")
PYEOF

# 2. Generate the Broken Draft ODT using odfpy
# We deliberately insert images with generic names ("Image1", "Image2")
# and incorrect anchoring (all as-char or paragraph without wrap)
echo "Generating draft_flyer.odt..."
python3 << 'PYEOF'
import os
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties, GraphicProperties
from odf.text import P, H
from odf.draw import Frame, Image

doc = OpenDocumentText()

# Create styles
h1style = Style(name="Heading 1", family="paragraph")
h1style.addElement(TextProperties(attributes={'fontsize':"24pt", 'fontweight':"bold"}))
doc.styles.addElement(h1style)

# Title (Plain text initially, agent must apply Heading 1)
doc.text.addElement(P(text="Luxury Villa at 123 Maple Drive"))

# 1. LOGO (Incorrectly placed inline or just floating awkwardly)
# We put it in a frame anchored to paragraph (wrong for a logo usually)
logo_frame = Frame(width="2cm", height="2cm", x="0cm", y="0cm", anchortype="paragraph")
logo_frame.setAttribute("name", "Image1") # Generic name
logo_img = Image(href="/tmp/logo.png")
logo_frame.addElement(logo_img)
doc.text.addElement(P(text=""))
doc.text.addElement(logo_frame)

# Body text
lorem = (
    "Nestled in the heart of the prestigious Highland Park district, this "
    "stunning 4-bedroom, 3-bath villa offers the perfect blend of modern "
    "luxury and timeless elegance. Spanning over 3,500 square feet, the "
    "open-concept living area features floor-to-ceiling windows that flood "
    "the space with natural light."
)
doc.text.addElement(P(text=lorem))

# 2. HOUSE PHOTO (Incorrectly placed - likely pushing text away or inline)
# We put it inline (as-char) which breaks the text flow for a large image
house_frame = Frame(width="10cm", height="7.5cm", anchortype="as-char")
house_frame.setAttribute("name", "Image2") # Generic name
house_img = Image(href="/tmp/house.png")
house_frame.addElement(house_img)
doc.text.addElement(P(text=""))
doc.text.addElement(house_frame)

lorem2 = (
    "The gourmet kitchen is a chef's dream, equipped with state-of-the-art "
    "Viking appliances, custom cabinetry, and a massive granite island. "
    "Step outside to your private oasis, complete with a heated saltwater "
    "pool and a spacious patio perfect for entertaining guests."
)
doc.text.addElement(P(text=lorem2))

# Closing
doc.text.addElement(P(text="Sincerely,"))

# 3. SIGNATURE (Incorrectly floating or anchored to paragraph)
# Anchored to paragraph instead of as-char, might float weirdly
sig_frame = Frame(width="5cm", height="1.25cm", anchortype="paragraph")
sig_frame.setAttribute("name", "Image3") # Generic name
sig_img = Image(href="/tmp/signature.png")
sig_frame.addElement(sig_img)
doc.text.addElement(sig_frame)

doc.text.addElement(P(text="Sarah Jenkins"))
doc.text.addElement(P(text="Senior Real Estate Agent"))

doc.save("/home/ga/Documents/draft_flyer.odt", addsuffix=False)
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/draft_flyer.odt

# 3. Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
# We assume the env has a way to launch writer.
# Using background process with display set
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/draft_flyer.odt > /tmp/writer.log 2>&1 &"

# 4. Wait for window and maximize
wait_for_window "LibreOffice Writer" 60
sleep 2

# Maximize window
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing Writer window ($WID)..."
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    focus_window "$WID"
fi

# 5. Record start state
date +%s > /tmp/task_start_time
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="