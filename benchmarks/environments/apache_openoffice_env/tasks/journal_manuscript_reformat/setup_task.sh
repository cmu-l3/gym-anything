#!/bin/bash
set -e

echo "=== Setting up Journal Manuscript Reformat Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Setup directories and clean state
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/manuscript_formatted.odt
rm -f /home/ga/Documents/manuscript_draft.odt
rm -f /home/ga/Documents/acs_style_guide.txt

# 2. Create the Style Guide text file
cat > /home/ga/Documents/acs_style_guide.txt << 'EOF'
ACS Journal Formatting Requirements for Environmental Science & Technology
==========================================================================

Before submitting your manuscript, ensure the following formatting is applied:

1. PAGE MARGINS: Set all margins (top, bottom, left, right) to 1 inch (2.54 cm).

2. FONT: Use Times New Roman, 12-point size for all body text.

3. LINE SPACING: Double-space the entire manuscript (200% line height).

4. LINE NUMBERING: Enable continuous line numbering throughout the document.
   Lines should be numbered sequentially from the first page to the last.
   (Tools > Line Numbering > Show numbering)

5. RUNNING HEADER: Add a running header on every page containing the
   shortened manuscript title: "Microplastic Accumulation in Great Lakes Tributaries"

6. SECTION HEADINGS: Apply "Heading 1" paragraph style to all main section
   headings: Abstract, Introduction, Materials and Methods, Results and
   Discussion, Conclusions, Acknowledgments, References.

7. SUBSECTION HEADINGS: Apply "Heading 2" paragraph style to all subsection
   headings within Materials and Methods and Results and Discussion.

8. REFERENCES: Format all reference entries with a hanging indent:
   0.5 inch (1.27 cm) left indent with -0.5 inch first-line indent.

9. PAGE NUMBERS: Add centered page numbers in the document footer.

10. Save the formatted manuscript as: manuscript_formatted.odt
    in the /home/ga/Documents/ directory.
EOF
chown ga:ga /home/ga/Documents/acs_style_guide.txt

# 3. Create the Draft Manuscript using Python (odfpy)
# We generate a "messy" file: manual bold formatting instead of Heading styles, 
# wrong margins, wrong font, no line numbers.
echo "Generating manuscript_draft.odt..."

python3 << 'PY_EOF'
import os
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties, PageLayout, PageLayoutProperties
from odf.text import P, H, Span

doc = OpenDocumentText()

# -- Create "Messy" Styles (Simulating bad formatting) --

# Standard Font (Liberation Sans, not Times)
s_standard = Style(name="Standard", family="paragraph")
s_standard.addElement(TextProperties(fontname="Liberation Sans", fontsize="12pt"))
doc.styles.addElement(s_standard)

# "Fake" Heading 1 (Just bold, big text - NOT a structural heading)
s_fake_h1 = Style(name="FakeH1", family="paragraph")
s_fake_h1.addElement(TextProperties(fontname="Liberation Sans", fontsize="14pt", fontweight="bold"))
s_fake_h1.addElement(ParagraphProperties(margintop="0.4cm", marginbottom="0.2cm"))
doc.automaticstyles.addElement(s_fake_h1)

# "Fake" Heading 2 (Bold Italic)
s_fake_h2 = Style(name="FakeH2", family="paragraph")
s_fake_h2.addElement(TextProperties(fontname="Liberation Sans", fontsize="12pt", fontweight="bold", fontstyle="italic"))
s_fake_h2.addElement(ParagraphProperties(margintop="0.3cm", marginbottom="0.1cm"))
doc.automaticstyles.addElement(s_fake_h2)

# Title Style
s_title = Style(name="DocTitle", family="paragraph")
s_title.addElement(TextProperties(fontname="Liberation Sans", fontsize="18pt", fontweight="bold"))
s_title.addElement(ParagraphProperties(textalign="center"))
doc.automaticstyles.addElement(s_title)

# Reference Style (No hanging indent)
s_ref = Style(name="ReferencePara", family="paragraph")
s_ref.addElement(TextProperties(fontname="Liberation Sans", fontsize="11pt"))
doc.automaticstyles.addElement(s_ref)

# -- Page Layout (Wrong Margins: 2cm instead of 2.54cm) --
pl = PageLayout(name="MyLayout")
pl.addElement(PageLayoutProperties(margintop="2cm", marginbottom="2cm", marginleft="2cm", marginright="2cm"))
doc.automaticstyles.addElement(pl)

# -- Content Generation --

# Title & Authors
doc.text.addElement(P(stylename=s_title, text="Microplastic Accumulation in Great Lakes Tributary Sediments: Spatial Distribution and Polymer Characterization"))
doc.text.addElement(P(stylename=s_standard, text=""))
doc.text.addElement(P(stylename=s_standard, text="Elena M. Vasquez, Marcus J. Chen, Aisha K. Ogundimu"))
doc.text.addElement(P(stylename=s_standard, text="Department of Environmental Science, University of Wisconsin–Madison"))
doc.text.addElement(P(stylename=s_standard, text=""))

# Content Structure
sections = [
    ("Abstract", "FakeH1", [
        "Microplastic pollution represents a growing concern in freshwater ecosystems. This study investigates sediment samples from six major tributaries feeding into Lake Michigan and Lake Superior. We quantified microplastic abundance and characterized polymer types using ATR-FTIR spectroscopy. Our results indicate a significant correlation between urbanization index and microplastic concentration, with polyethylene and polypropylene being the dominant polymer types found. These findings suggest that tributaries act as significant sinks and transport pathways for terrestrial microplastics entering the Great Lakes system."
    ]),
    ("Introduction", "FakeH1", [
        "The accumulation of plastic debris in aquatic environments has become a global environmental issue (Eriksen et al., 2013). While marine microplastics have been extensively studied, freshwater systems remain comparatively under-researched. The Great Lakes, holding 21% of the world's surface fresh water, are particularly vulnerable to anthropogenic contamination.",
        "Previous studies have documented surface water concentrations, but sediment sinks remain poorly understood. This study aims to fill this gap by analyzing sediment cores from key tributaries."
    ]),
    ("Materials and Methods", "FakeH1", [
        ("Study Sites and Sampling Design", "FakeH2", "Sediment samples were collected from the Milwaukee River, Menominee River, Fox River, Root River, Sheboygan River, and Manitowoc River. At each site, triplicate sediment cores were taken using a box corer."),
        ("Sample Processing and Analysis", "FakeH2", "Samples were dried at 60°C for 48 hours. Organic matter was digested using wet peroxide oxidation (WPO) following NOAA protocols. Density separation was performed using NaI solution (1.6 g/cm3)."),
        ("Quality Assurance and Quality Control", "FakeH2", "Strict contamination control measures were implemented. All laboratory work was conducted in a laminar flow hood. Cotton lab coats were worn at all times.")
    ]),
    ("Results and Discussion", "FakeH1", [
        ("Spatial Distribution Patterns", "FakeH2", "Microplastic concentrations ranged from 150 to 2,340 particles/kg dry sediment. The highest concentrations were observed in the Milwaukee River estuary, correlating with high population density."),
        ("Polymer Composition Analysis", "FakeH2", "ATR-FTIR analysis revealed that Polyethylene (PE) and Polypropylene (PP) accounted for 65% of all identified particles. Polystyrene (PS) and PET were also frequently detected."),
        ("Environmental Implications", "FakeH2", "The dominance of low-density polymers in benthic sediments suggests that biofouling plays a critical role in the vertical transport of microplastics.")
    ]),
    ("Conclusions", "FakeH1", [
        "This study confirms that tributaries are significant reservoirs of microplastic pollution. Management strategies must focus on watershed-level mitigation."
    ]),
    ("Acknowledgments", "FakeH1", [
        "This research was supported by the National Science Foundation (Grant No. 123456) and the Wisconsin Department of Natural Resources."
    ]),
    ("References", "FakeH1", [])
]

# Build Text
for title, style, content_list in sections:
    # Add Section Header
    doc.text.addElement(P(stylename=style, text=title))
    
    # Add Content
    for item in content_list:
        if isinstance(item, tuple): # Subsection
            sub_title, sub_style, sub_text = item
            doc.text.addElement(P(stylename=sub_style, text=sub_title))
            doc.text.addElement(P(stylename=s_standard, text=sub_text))
        else: # Normal paragraph
            doc.text.addElement(P(stylename=s_standard, text=item))

# Add References (Plain formatting, no hanging indent)
refs = [
    "1. Eriksen, M.; Mason, S.; Wilson, S.; Box, C.; Zellers, A.; Edwards, W.; Casillas, H.; Amato, S. Microplastic pollution in the surface waters of the Laurentian Great Lakes. Mar. Pollut. Bull. 2013, 77, 177-182.",
    "2. Baldwin, A. K.; Corsi, S. R.; Mason, S. A. Plastic debris in 29 Great Lakes tributaries: Relations to watershed attributes and hydrology. Environ. Sci. Technol. 2016, 50, 10377-10385.",
    "3. Hendrickson, E.; Minor, E. C.; Schreiner, K. Microplastic abundance and composition in western Lake Superior as determined via microscopy and pyrolysis GC/MS. Environ. Sci. Technol. 2018, 52, 1787-1796.",
    "4. Rochman, C. M. Microplastics research—from sinking to rising. Science 2018, 360, 28-29.",
    "5. Hidalgo-Ruz, V.; Gutow, L.; Thompson, R. C.; Thiel, M. Microplastics in the marine environment: a review of the methods used for identification and quantification. Environ. Sci. Technol. 2012, 46, 3060-3075.",
    "6. Lusher, A. L.; Tirelli, V.; O'Connor, I.; Officer, R. Microplastics in Arctic polar waters: the first reported values of particles in surface and sub-surface samples. Sci. Rep. 2015, 5, 14947."
]
# Generate 19 more dummy refs to reach 25
for i in range(7, 26):
    refs.append(f"{i}. Placeholder Author {i}. Title of the paper {i}. Journal of Environmental Science {2010+i}, {i}, 100-110.")

for ref in refs:
    doc.text.addElement(P(stylename=s_ref, text=ref))

doc.save("/home/ga/Documents/manuscript_draft.odt")
PY_EOF
chown ga:ga /home/ga/Documents/manuscript_draft.odt

# 4. Launch OpenOffice Writer with the draft loaded
echo "Launching OpenOffice Writer..."
# We use nohup and redirect output to prevent blocking
nohup sudo -u ga DISPLAY=:1 /opt/openoffice4/program/soffice --writer /home/ga/Documents/manuscript_draft.odt > /dev/null 2>&1 &

# 5. Wait for window and maximize
echo "Waiting for OpenOffice..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
        echo "Window found."
        break
    fi
    sleep 1
done

echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 6. Capture initial state
date +%s > /tmp/task_start_time.txt
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="