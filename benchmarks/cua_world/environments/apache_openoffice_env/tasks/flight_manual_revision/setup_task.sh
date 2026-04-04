#!/bin/bash
set -e
echo "=== Setting up Flight Manual Revision Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare directories and clean state
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/GOM_Ch7_ColdWeather.odt
rm -f /home/ga/Documents/GOM_Ch7_Rev05.odt
rm -f /home/ga/Documents/revision_order.json

# 2. Generate the Input ODT file (GOM_Ch7_ColdWeather.odt)
# We create a valid ODT file using Python to ensure it opens correctly in OpenOffice
echo "Generating input ODT file..."
python3 << 'PYEOF'
import zipfile
import os
import time

def create_manifest():
    return """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
 <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
 <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
 <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
</manifest:manifest>"""

def create_content():
    return """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" xmlns:dr3d="urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0" xmlns:math="http://www.w3.org/1998/Math/MathML" xmlns:form="urn:oasis:names:tc:opendocument:xmlns:form:1.0" xmlns:script="urn:oasis:names:tc:opendocument:xmlns:script:1.0" office:version="1.2">
 <office:body>
  <office:text>
   <text:h text:style-name="Heading_20_1" text:outline-level="1">7.0 COLD WEATHER OPERATIONS</text:h>
   <text:p text:style-name="Standard">This chapter details the procedures for operating in icing conditions.</text:p>
   <text:h text:style-name="Heading_20_2" text:outline-level="2">7.4 PRE-FLIGHT PROCEDURES</text:h>
   <text:h text:style-name="Heading_20_3" text:outline-level="3">7.4.1 Pre-Takeoff Check</text:h>
   <text:p text:style-name="Standard">The Pilot in Command must conduct a visual inspection of wings and control surfaces immediately prior to takeoff. If any frost, ice, or snow is detected, the aircraft must be de-iced. The visual check must be performed from the cabin windows or by ground personnel.</text:p>
   <text:p text:style-name="Warning_Para">WARNING</text:p>
   <text:p text:style-name="Standard">Failure to remove contamination may result in loss of lift and control.</text:p>
   <text:h text:style-name="Heading_20_3" text:outline-level="3">7.4.2 Holdover Times</text:h>
   <text:p text:style-name="Standard">Consult current FAA Holdover Time guidelines.</text:p>
  </office:text>
 </office:body>
</office:document-content>"""

def create_styles():
    return """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" xmlns:dr3d="urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0" xmlns:math="http://www.w3.org/1998/Math/MathML" xmlns:form="urn:oasis:names:tc:opendocument:xmlns:form:1.0" xmlns:script="urn:oasis:names:tc:opendocument:xmlns:script:1.0" office:version="1.2">
 <office:styles>
  <style:style style:name="Standard" style:family="paragraph" style:class="text"/>
  <style:style style:name="Heading_20_1" style:display-name="Heading 1" style:family="paragraph" style:parent-style-name="Standard" style:next-style-name="Standard" style:class="text">
   <style:text-properties fo:font-size="18pt" fo:font-weight="bold"/>
  </style:style>
  <style:style style:name="Heading_20_2" style:display-name="Heading 2" style:family="paragraph" style:parent-style-name="Standard" style:next-style-name="Standard" style:class="text">
   <style:text-properties fo:font-size="14pt" fo:font-weight="bold"/>
  </style:style>
  <style:style style:name="Heading_20_3" style:display-name="Heading 3" style:family="paragraph" style:parent-style-name="Standard" style:next-style-name="Standard" style:class="text">
   <style:text-properties fo:font-size="12pt" fo:font-weight="bold"/>
  </style:style>
  <style:style style:name="Warning_Para" style:family="paragraph" style:parent-style-name="Standard">
   <style:text-properties fo:color="#ff0000"/>
  </style:style>
 </office:styles>
 <office:master-styles>
  <style:master-page style:name="Standard" style:page-layout-name="Mpm1">
   <style:header>
    <text:p text:style-name="Standard">Stratos Air Charter GOM | Revision: 04 | Date: 2024-01-15</text:p>
   </style:header>
  </style:master-page>
 </office:master-styles>
</office:document-styles>"""

output_path = "/home/ga/Documents/GOM_Ch7_ColdWeather.odt"
with zipfile.ZipFile(output_path, 'w') as zf:
    zf.writestr('mimetype', 'application/vnd.oasis.opendocument.text')
    zf.writestr('META-INF/manifest.xml', create_manifest())
    zf.writestr('content.xml', create_content())
    zf.writestr('styles.xml', create_styles())

os.chmod(output_path, 0o666)
PYEOF

chown ga:ga /home/ga/Documents/GOM_Ch7_ColdWeather.odt

# 3. Create Instruction JSON
cat > /home/ga/Documents/revision_order.json << 'EOF'
{
    "order_id": "REV-2024-005",
    "target_document": "GOM Chapter 7 - Cold Weather Operations",
    "instructions": {
        "update_section": "7.4.1",
        "new_text": "The Pilot in Command must conduct a tactile check of critical surfaces (wings, tail, control surfaces) within 5 minutes of takeoff if the OAT is below 5°C or if visible moisture is present. Visual inspection alone is not sufficient in conditions conducive to clear ice. This check requires physical contact with the aircraft surface.",
        "formatting_requirements": [
            "Apply a visual revision bar (Left Border, width >= 1.00pt) to the updated 7.4.1 paragraph.",
            "Format the 'WARNING' paragraph with a Box Border (all 4 sides) and Bold text.",
            "Update Header Revision Number to '05' and Date to today."
        ]
    }
}
EOF
chown ga:ga /home/ga/Documents/revision_order.json

# 4. Anti-gaming timestamps
date +%s > /tmp/task_start_time.txt
# Record initial state of the doc (size/hash)
sha256sum /home/ga/Documents/GOM_Ch7_ColdWeather.odt > /tmp/initial_hash.txt

# 5. Launch OpenOffice Writer (optional but helpful context)
# We don't open the file automatically, letting the agent do it as per description
if ! pgrep -f "soffice" > /dev/null; then
     su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
     sleep 5
fi

# 6. Maximize
DISPLAY=:1 wmctrl -r "OpenOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="