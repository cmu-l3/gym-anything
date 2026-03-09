#!/bin/bash
# Setup script for academic_thesis_footnotes task
# Generates a draft ODT file with placeholder markers [1]...[5] and a JSON source file.

echo "=== Setting up Academic Thesis Footnotes Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# cleanup
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop
rm -f /home/ga/Documents/Erie_Canal_Draft.odt
rm -f /home/ga/Documents/Chapter_2_Final.odt
rm -f /home/ga/Documents/citation_source.json

# 1. Create the JSON source file
cat > /home/ga/Documents/citation_source.json << 'JSONEOF'
{
    "1": "Peter L. Bernstein, Wedding of the Waters: The Erie Canal and the Making of a Great Nation (New York: W.W. Norton, 2005), 45.",
    "2": "Carol Sheriff, The Artificial River: The Erie Canal and the Paradox of Progress (New York: Hill and Wang, 1996), 12.",
    "3": "Ronald E. Shaw, Erie Water West: A History of the Erie Canal (Lexington: University of Kentucky Press, 1966), 88.",
    "4": "Robert G. Albion, The Rise of New York Port (New York: Scribner, 1939), 202.",
    "5": "Bernstein, Wedding of the Waters, 112."
}
JSONEOF
chown ga:ga /home/ga/Documents/citation_source.json

# 2. Create the draft ODT file using Python to ensure valid structure
# We construct a minimal ODT with specific text content containing [1] markers.
python3 << 'PYEOF'
import zipfile
import os
import time

filename = "/home/ga/Documents/Erie_Canal_Draft.odt"

# Minimal ODT components
mimetype = b"application/vnd.oasis.opendocument.text"

manifest_xml = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
 <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
 <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
 <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
</manifest:manifest>"""

# Content with placeholders
content_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" xmlns:dr3d="urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0" xmlns:math="http://www.w3.org/1998/Math/MathML" xmlns:form="urn:oasis:names:tc:opendocument:xmlns:form:1.0" xmlns:script="urn:oasis:names:tc:opendocument:xmlns:script:1.0" xmlns:ooo="http://openoffice.org/2004/office" xmlns:ooow="http://openoffice.org/2004/writer" xmlns:oooc="http://openoffice.org/2004/calc" xmlns:dom="http://www.w3.org/2001/xml-events" xmlns:xforms="http://www.w3.org/2002/xforms" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:rpt="http://openoffice.org/2005/report" xmlns:of="urn:oasis:names:tc:opendocument:xmlns:of:1.2" xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:grddl="http://www.w3.org/2003/g/data-view#" xmlns:tableooo="http://openoffice.org/2009/table" xmlns:field="urn:openoffice:names:experimental:ooo-ms-interop:xmlns:field:1.0" office:version="1.2">
 <office:body>
  <office:text>
   <text:p text:style-name="Standard">Chapter 2: The Wedding of the Waters</text:p>
   <text:p text:style-name="Standard"/>
   <text:p text:style-name="Standard">The completion of the Erie Canal in 1825 marked a turning point in American history. Governor DeWitt Clinton, whose vision had driven the project despite ridicule, presided over the ceremonies. The canal linked the waters of Lake Erie to the Hudson River, effectively opening the Midwest to global markets [1].</text:p>
   <text:p text:style-name="Standard"/>
   <text:p text:style-name="Standard">Critics had dubbed the project "Clinton's Ditch," arguing that the engineering challenges were insurmountable. Yet, the canal engineers, many of whom were self-taught, overcame obstacles like the Niagara Escarpment through the famous Lockport Flight [2]. The economic impact was immediate. Freight rates dropped by over 90%, transforming New York City into the nation's premier port [3].</text:p>
   <text:p text:style-name="Standard"/>
   <text:p text:style-name="Standard">The social impact was equally profound. The canal corridor became a hotbed of reform movements, from abolitionism to women's suffrage, leading some historians to label it the "Burned-Over District" [4]. However, the construction also displaced indigenous populations and disrupted local ecosystems, a legacy that is often overshadowed by the economic triumph [5].</text:p>
   <text:p text:style-name="Standard"/>
   <text:p text:style-name="Standard"/>
   <text:p text:style-name="Standard">Bibliography</text:p>
   <text:p text:style-name="Standard">Albion, Robert G. The Rise of New York Port. New York: Scribner, 1939.</text:p>
   <text:p text:style-name="Standard">Bernstein, Peter L. Wedding of the Waters: The Erie Canal and the Making of a Great Nation. New York: W.W. Norton, 2005.</text:p>
   <text:p text:style-name="Standard">Shaw, Ronald E. Erie Water West: A History of the Erie Canal. Lexington: University of Kentucky Press, 1966.</text:p>
   <text:p text:style-name="Standard">Sheriff, Carol. The Artificial River: The Erie Canal and the Paradox of Progress. New York: Hill and Wang, 1996.</text:p>
  </office:text>
 </office:body>
</office:document-content>"""

styles_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
 <office:styles>
  <style:style style:name="Standard" style:family="paragraph" style:class="text"/>
  <style:style style:name="Heading_20_1" style:display-name="Heading 1" style:family="paragraph" style:parent-style-name="Standard" style:class="text">
   <style:text-properties fo:font-size="16pt" fo:font-weight="bold"/>
  </style:style>
 </office:styles>
</office:document-styles>"""

with zipfile.ZipFile(filename, "w") as zf:
    zf.writestr("mimetype", mimetype)
    zf.writestr("META-INF/manifest.xml", manifest_xml)
    zf.writestr("content.xml", content_xml)
    zf.writestr("styles.xml", styles_xml)

print(f"Created {filename}")
PYEOF

chown ga:ga /home/ga/Documents/Erie_Canal_Draft.odt

# 3. Ensure OpenOffice Desktop Shortcut
mkdir -p /home/ga/Desktop
if [ -f /usr/share/applications/openoffice4-writer.desktop ]; then
    cp /usr/share/applications/openoffice4-writer.desktop /home/ga/Desktop/
else
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
MimeType=application/vnd.oasis.opendocument.text;
DESKTOP
fi
chmod +x /home/ga/Desktop/*.desktop
chown ga:ga /home/ga/Desktop/*.desktop

# 4. Record task start
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="