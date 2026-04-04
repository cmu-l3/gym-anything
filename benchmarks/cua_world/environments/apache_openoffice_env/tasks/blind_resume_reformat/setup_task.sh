#!/bin/bash
echo "=== Setting up Blind Resume Reformat Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create directory structure
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/candidate_raw.odt
rm -f /home/ga/Documents/Candidate_CRA-994_Blind.odt
rm -f /home/ga/Documents/apex_style_guide.txt

# 3. Create the raw resume ODT file using Python to write raw XML
# We use direct formatting (bold, font size) instead of styles to simulate a "messy" raw file
# that needs fixing.
python3 << 'PYEOF'
import zipfile
import os

OUTPUT_PATH = "/home/ga/Documents/candidate_raw.odt"

MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text" manifest:version="1.2"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
</manifest:manifest>"""

# Content with direct formatting (simulating raw user input)
# Note: "text:style-name" points to automatic styles, not semantic styles like Heading 1
CONTENT = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" xmlns:dr3d="urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0" xmlns:math="http://www.w3.org/1998/Math/MathML" xmlns:form="urn:oasis:names:tc:opendocument:xmlns:form:1.0" xmlns:script="urn:oasis:names:tc:opendocument:xmlns:script:1.0" xmlns:ooo="http://openoffice.org/2004/office" xmlns:ooow="http://openoffice.org/2004/writer" xmlns:oooc="http://openoffice.org/2004/calc" xmlns:dom="http://www.w3.org/2001/xml-events" xmlns:xforms="http://www.w3.org/2002/xforms" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:rpt="http://openoffice.org/2005/report" xmlns:of="urn:oasis:names:tc:opendocument:xmlns:of:1.2" xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:grddl="http://www.w3.org/2003/g/data-view#" xmlns:tableooo="http://openoffice.org/2009/table" xmlns:field="urn:openoffice:names:experimental:ooo-ms-interop:xmlns:field:1.0" office:version="1.2">
  <office:automatic-styles>
    <style:style style:name="P1" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties fo:font-weight="bold" fo:font-size="16pt"/>
      <style:paragraph-properties fo:text-align="center"/>
    </style:style>
    <style:style style:name="P2" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties fo:font-size="10pt"/>
      <style:paragraph-properties fo:text-align="center"/>
    </style:style>
    <style:style style:name="P3" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties fo:font-weight="bold" fo:font-size="14pt" fo:color="#000080"/>
      <style:paragraph-properties fo:margin-top="0.2in" fo:margin-bottom="0.1in"/>
    </style:style>
    <style:style style:name="P4" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties fo:font-weight="bold" fo:font-size="12pt"/>
    </style:style>
    <style:style style:name="P_List" style:family="paragraph" style:parent-style-name="Standard">
      <style:text-properties fo:font-size="11pt"/>
    </style:style>
  </office:automatic-styles>
  <office:body>
    <office:text>
      <text:p text:style-name="P1">Marcus Reynolds</text:p>
      <text:p text:style-name="P2">San Francisco, CA | 415-555-0199 | marcus.reynolds@email.com</text:p>
      <text:p text:style-name="P2">linkedin.com/in/mreynolds</text:p>
      <text:p text:style-name="Standard"/>
      
      <text:p text:style-name="P3">Professional Summary</text:p>
      <text:p text:style-name="Standard">Results-oriented Senior Cloud Architect with 10+ years of experience designing scalable AWS and Azure infrastructure. Proven track record in migrating on-premise legacy systems to cloud-native microservices architectures. Expert in DevOps methodologies, CI/CD pipelines, and infrastructure as code.</text:p>
      
      <text:p text:style-name="P3">Technical Skills</text:p>
      <text:p text:style-name="P_List">Cloud Platforms: AWS (Certified Solutions Architect), Azure, Google Cloud Platform</text:p>
      <text:p text:style-name="P_List">Containerization: Docker, Kubernetes, ECS, EKS, Helm Charts</text:p>
      <text:p text:style-name="P_List">IaC &amp; Config Mgmt: Terraform, CloudFormation, Ansible, Puppet, Chef</text:p>
      <text:p text:style-name="P_List">CI/CD Tools: Jenkins, GitLab CI, GitHub Actions, CircleCI, ArgoCD</text:p>
      <text:p text:style-name="P_List">Programming: Python, Go, Bash, JavaScript, TypeScript, Java</text:p>
      <text:p text:style-name="P_List">Databases: PostgreSQL, MongoDB, DynamoDB, Redis, Elasticsearch</text:p>
      
      <text:p text:style-name="P3">Professional Experience</text:p>
      
      <text:p text:style-name="P4">Senior Cloud Solutions Architect</text:p>
      <text:p text:style-name="Standard">TechFlow Solutions | San Jose, CA | 2019 - Present</text:p>
      <text:p text:style-name="Standard">- Led the migration of a monolithic e-commerce platform to a microservices architecture on AWS EKS, reducing operational costs by 40%.</text:p>
      <text:p text:style-name="Standard">- Designed and implemented a multi-region disaster recovery strategy with an RTO of 15 minutes.</text:p>
      <text:p text:style-name="Standard">- Mentored a team of 8 DevOps engineers and established best practices for IaC using Terraform.</text:p>
      
      <text:p text:style-name="P4">DevOps Engineer</text:p>
      <text:p text:style-name="Standard">DataSphere Inc. | Austin, TX | 2016 - 2019</text:p>
      <text:p text:style-name="Standard">- Automated deployment pipelines using Jenkins and Ansible, reducing deployment time from 2 hours to 15 minutes.</text:p>
      <text:p text:style-name="Standard">- Managed a fleet of 500+ EC2 instances and optimized reserved instance purchasing to save $120k annually.</text:p>
      
      <text:p text:style-name="P4">Systems Administrator</text:p>
      <text:p text:style-name="Standard">NexGen Startups | Boulder, CO | 2013 - 2016</text:p>
      <text:p text:style-name="Standard">- Administered Linux servers (RHEL/CentOS) and managed network security policies.</text:p>
      
      <text:p text:style-name="P3">Education</text:p>
      <text:p text:style-name="P4">Bachelor of Science in Computer Science</text:p>
      <text:p text:style-name="Standard">University of Colorado Boulder | 2013</text:p>
    </office:text>
  </office:body>
</office:document-content>"""

STYLES_XML = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" office:version="1.2">
  <office:styles>
    <style:default-style style:family="paragraph"/>
  </office:styles>
</office:document-styles>"""

with zipfile.ZipFile(OUTPUT_PATH, 'w') as zf:
    zf.writestr('mimetype', 'application/vnd.oasis.opendocument.text')
    zf.writestr('META-INF/manifest.xml', MANIFEST)
    zf.writestr('content.xml', CONTENT)
    zf.writestr('styles.xml', STYLES_XML)
    
os.chown(OUTPUT_PATH, 1000, 1000) # ga:ga
PYEOF

# 4. Create Style Guide text file
cat > /home/ga/Documents/apex_style_guide.txt << 'EOF'
*** APEX SYSTEMS - CANDIDATE SUBMISSION STYLE GUIDE ***

1. ANONYMIZATION
   - Remove ALL contact information (Address, Phone, Email, Links).
   - Remove candidate Name.
   - Add Candidate ID at the top (Title style).

2. FORMATTING
   - Section Headers: Use 'Heading 1' style.
   - Job Titles: Use 'Heading 2' style.
   - Skills: Must be presented in a Table format (2 columns), not a list.
   - Font: Arial 11pt for body text.

3. BRANDING
   - Footer: Must contain "Confidential Representation - Apex Systems" and page number.
EOF
chown ga:ga /home/ga/Documents/apex_style_guide.txt

# 5. Record initial state
date +%s > /tmp/task_start_time.txt
echo "Setup complete. Files created."

# 6. Ensure OpenOffice is ready (but don't open the file, let agent do it)
# Just creating the desktop shortcut to be helpful
if [ -x "/opt/openoffice4/program/soffice" ]; then
    cp /usr/share/applications/openoffice4-writer.desktop /home/ga/Desktop/ 2>/dev/null || true
    chmod +x /home/ga/Desktop/*.desktop 2>/dev/null || true
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png