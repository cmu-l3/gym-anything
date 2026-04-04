#!/bin/bash
# Setup script for genealogy_manuscript_index task
# Creates a draft manuscript ODT and a JSON list of terms to index

echo "=== Setting up Genealogy Manuscript Index Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up any previous task artifacts
rm -f /home/ga/Documents/manuscript_draft.odt 2>/dev/null || true
rm -f /home/ga/Documents/Holloway_Chapter4_Indexed.odt 2>/dev/null || true
rm -f /home/ga/Documents/terms_to_index.json 2>/dev/null || true

# 1. Create the JSON terms file
cat > /home/ga/Documents/terms_to_index.json << 'JSONEOF'
[
  "Jeremiah Holloway",
  "Martha Holloway",
  "Cumberland Gap",
  "Oxen",
  "Fort Laramie",
  "Independence Rock",
  "Chimney Rock",
  "Oregon Trail",
  "Cholera",
  "Wagon"
]
JSONEOF
chown ga:ga /home/ga/Documents/terms_to_index.json

# 2. Create the manuscript draft ODT using Python to ensure valid XML structure
# We construct a simple ODT zip file with specific content containing the terms.

python3 << 'PYEOF'
import zipfile
import os
import time

OUTPUT_PATH = "/home/ga/Documents/manuscript_draft.odt"

# The story text containing all the terms to be indexed
STORY_TITLE = "Chapter 4: The Crossing"
STORY_CONTENT = [
    "The spring of 1842 brought with it a sense of foreboding for the Holloway clan. Jeremiah Holloway had spent the winter mending the tack and preparing the Wagon for the arduous journey ahead. He knew that once they left the comfort of their Virginia homestead, there would be no turning back. Martha Holloway, stoic as ever, packed the salted pork and flour, her eyes scanning the horizon where the sun dipped low.",
    "Their route would take them through the Cumberland Gap, a passage that had tested the mettle of many before them. The Oxen were restless, sensing the anxiety of their masters. These beasts were the engine of their migration, strong but prone to stubbornness when the mud grew deep.",
    "Weeks turned into months. By the time they reached the Platte River, the landscape had flattened into an endless sea of grass. The Oregon Trail was a dusty ribbon stretching into infinity. Landmarks became the only way to mark time. First came Chimney Rock, a spire piercing the blue sky, visible for days before they arrived at its base.",
    "Next was Fort Laramie, a bustle of trade and news. Here, Jeremiah traded for fresh supplies, hearing rumors of trouble ahead. But the most significant milestone was Independence Rock. It was said that if you didn't reach it by the Fourth of July, the winter snows would trap you in the mountains. Jeremiah carved his initials into the granite, a testament to their survival thus far.",
    "But the trail exacted a heavy toll. Cholera swept through the wagon train in late August, claiming three families in a week. Martha tended to the sick with a rag soaked in vinegar, her prayers whispered into the wind. They pressed on, for stopping meant death."
]

# Basic ODT manifest
MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
 <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
 <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
 <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
 <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
</manifest:manifest>"""

# content.xml construction
content_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" xmlns:dr3d="urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0" xmlns:math="http://www.w3.org/1998/Math/MathML" xmlns:form="urn:oasis:names:tc:opendocument:xmlns:form:1.0" xmlns:script="urn:oasis:names:tc:opendocument:xmlns:script:1.0" xmlns:ooo="http://openoffice.org/2004/office" xmlns:ooow="http://openoffice.org/2004/writer" xmlns:oooc="http://openoffice.org/2004/calc" xmlns:dom="http://www.w3.org/2001/xml-events" xmlns:xforms="http://www.w3.org/2002/xforms" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:rpt="http://openoffice.org/2005/report" xmlns:of="urn:oasis:names:tc:opendocument:xmlns:of:1.2" xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:grddl="http://www.w3.org/2003/g/data-view#" xmlns:tableooo="http://openoffice.org/2009/table" xmlns:field="urn:openoffice:names:experimental:ooo-ms-interop:xmlns:field:1.0" xmlns:formx="urn:openoffice:names:experimental:ooxml-odf-interop:xmlns:form:1.0" xmlns:css3t="http://www.w3.org/TR/css3-text/" office:version="1.2">
 <office:body>
  <office:text>"""

# Add Title (Plain Paragraph initially - task is to make it Heading 1)
content_xml += f'<text:p text:style-name="Standard">{STORY_TITLE}</text:p>'

# Add Body Paragraphs
for para in STORY_CONTENT:
    content_xml += f'<text:p text:style-name="Standard">{para}</text:p>'

content_xml += """  </office:text>
 </office:body>
</office:document-content>"""

# styles.xml (Basic)
styles_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" office:version="1.2">
 <office:styles>
  <style:style style:name="Standard" style:family="paragraph" style:class="text"/>
  <style:style style:name="Heading_20_1" style:display-name="Heading 1" style:family="paragraph" style:parent-style-name="Standard" style:next-style-name="Standard" style:class="text">
   <style:text-properties fo:font-size="130%" fo:font-weight="bold"/>
  </style:style>
 </office:styles>
</office:document-styles>"""

# Create the ODT file
with zipfile.ZipFile(OUTPUT_PATH, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('mimetype', 'application/vnd.oasis.opendocument.text')
    zf.writestr('META-INF/manifest.xml', MANIFEST)
    zf.writestr('content.xml', content_xml)
    zf.writestr('styles.xml', styles_xml)
    zf.writestr('meta.xml', '<office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" office:version="1.2"/>')

print(f"Created {OUTPUT_PATH}")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/manuscript_draft.odt

# 3. Create Desktop shortcut if missing
if [ -x "/opt/openoffice4/program/soffice" ]; then
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# 4. Record initial state
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Manuscript: /home/ga/Documents/manuscript_draft.odt"
echo "Terms List: /home/ga/Documents/terms_to_index.json"