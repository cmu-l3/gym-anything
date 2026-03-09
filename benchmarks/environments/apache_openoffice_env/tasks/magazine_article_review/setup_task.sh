#!/bin/bash
echo "=== Setting up Magazine Article Review Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous artifacts
rm -f /home/ga/Documents/AI_Draft_2024.odt 2>/dev/null || true
rm -f /home/ga/Documents/AI_Draft_Reviewed.odt 2>/dev/null || true

# Generate the starting ODT file using Python and odfpy
# We use a python script to ensure a valid ODT structure with specific content
cat << 'PYEOF' > /tmp/generate_draft.py
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import H, P, Span

doc = OpenDocumentText()

# Create styles
h1style = Style(name="Heading 1", family="paragraph")
h1style.addElement(TextProperties(attributes={'fontsize':"24pt", 'fontweight':"bold"}))
doc.styles.addElement(h1style)

pstyle = Style(name="Text Body", family="paragraph")
pstyle.addElement(TextProperties(attributes={'fontsize':"12pt"}))
doc.styles.addElement(pstyle)

# Add Content
# Title
h = H(outlinelevel=1, stylename=h1style, text="Computer Brains are Here")
doc.text.addElement(h)

# Para 1
p1 = P(stylename=pstyle, text="In recent years, Artificial Intelligence has made massive strides. Large Language Models (LLMs) like GPT-4 have changed how we work.")
doc.text.addElement(p1)

# Para 2 (Contains Typo)
p2 = P(stylename=pstyle)
p2.addText("The underlying technology, known as ")
# Bold the typo to make it slightly distinct in structure, though visual only
bold_span = Span(stylename=pstyle) 
p2.addText("Generatve") # Typo here
p2.addText(" Pre-trained Transformers, predicts the next token in a sequence with uncanny accuracy.")
doc.text.addElement(p2)

# Para 3 (To be deleted)
p3 = P(stylename=pstyle, text="I remember watching Terminator 2 in theaters. The liquid metal robot was scary but also cool. It made me think about the future of robotics and how we might one day fight skew-net or whatever it was called.")
doc.text.addElement(p3)

# Para 4
p4 = P(stylename=pstyle, text="Businesses are now adopting these tools rapidly to automate customer service and content generation.")
doc.text.addElement(p4)

doc.save("/home/ga/Documents/AI_Draft_2024.odt")
PYEOF

# Run the generator
echo "Generating draft document..."
python3 /tmp/generate_draft.py
chown ga:ga /home/ga/Documents/AI_Draft_2024.odt

# Create desktop shortcut for Writer if not exists
if [ ! -f "/home/ga/Desktop/openoffice-writer.desktop" ]; then
    if [ -f "/usr/share/applications/openoffice4-writer.desktop" ]; then
        cp "/usr/share/applications/openoffice4-writer.desktop" /home/ga/Desktop/
        chmod +x /home/ga/Desktop/openoffice4-writer.desktop
    elif [ -x "/opt/openoffice4/program/soffice" ]; then
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
        chmod +x /home/ga/Desktop/openoffice-writer.desktop
    fi
    chown -R ga:ga /home/ga/Desktop
fi

# Timestamp start
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="