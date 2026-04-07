#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Water Quality CCR Compilation Task ==="

# Create directories
install -d -o ga -g ga /home/ga/Desktop

# Kill any existing Calligra processes
kill_calligra_processes

# Delete stale output BEFORE recording timestamp
rm -f /home/ga/Desktop/millbrook_ccr_2025.odt

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any leftover source files from previous runs
rm -f /home/ga/Desktop/lab_results_2025.odt
rm -f /home/ga/Desktop/ccr_narrative_sections.odt
rm -f /home/ga/Desktop/epa_ccr_format_guide.txt

# ------------------------------------------------------------------
# Generate the lab results source file (plain, unformatted ODF)
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add(text=""):
    doc.text.addElement(P(text=text))

add("CITY OF MILLBROOK WATER UTILITY")
add("Water Quality Testing Results -- Calendar Year 2025")
add("Laboratory: Millbrook Environmental Services, LLC (Lab ID: NC-2847)")
add("")
add("The following data represents results from samples collected January through")
add("December 2025 at 42 monitoring points across the Millbrook distribution system.")
add("")
add("Detected Contaminants:")
add("")
add("Contaminant | Unit | MCL | MCLG | Level Detected | Range | Violation")
add("Barium | ppm | 2 | 2 | 0.04 | 0.02-0.06 | No")
add("Fluoride | ppm | 4 | 4 | 0.72 | 0.5-0.9 | No")
add("Nitrate (as Nitrogen) | ppm | 10 | 10 | 3.8 | 1.2-5.1 | No")
add("Copper (90th percentile) | ppm | AL=1.3 | 1.3 | 0.12 | ND-0.45 | No")
add("Lead (90th percentile) | ppb | AL=15 | 0 | 8.2 | ND-18.5 | Yes")
add("Total Trihalomethanes (TTHM) | ppb | 80 | N/A | 62 | 38-72 | No")
add("Haloacetic Acids (HAA5) | ppb | 60 | N/A | 48 | 22-58 | No")
add("Turbidity | NTU | TT | N/A | 0.3 | 0.1-0.5 | No")
add("")
add("Abbreviations: MCL = Maximum Contaminant Level, MCLG = Maximum Contaminant")
add("Level Goal, AL = Action Level, TT = Treatment Technique, ND = Not Detected,")
add("ppm = parts per million, ppb = parts per billion, NTU = Nephelometric")
add("Turbidity Units")

doc.save("/home/ga/Desktop/lab_results_2025.odt")
print("Created lab_results_2025.odt")
PYEOF

# ------------------------------------------------------------------
# Generate the narrative sections file with intentionally messy formatting
# Each section uses a different font/size/alignment to simulate
# multiple engineers contributing draft content
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P

doc = OpenDocumentText()

# --- Style: Engineering system output (monospace, small) ---
mono_style = Style(name="MonoPara", family="paragraph")
mono_style.addElement(ParagraphProperties(textalign="left"))
mono_style.addElement(TextProperties(fontname="Liberation Mono", fontsize="10pt",
                                     fontnameasian="Liberation Mono", fontsizeasian="10pt",
                                     fontnamecomplex="Liberation Mono", fontsizecomplex="10pt"))
doc.automaticstyles.addElement(mono_style)

# --- Style: Bold section label in monospace context ---
mono_bold_style = Style(name="MonoBold", family="paragraph")
mono_bold_style.addElement(ParagraphProperties(textalign="left"))
mono_bold_style.addElement(TextProperties(fontname="Liberation Mono", fontsize="10pt",
                                          fontweight="bold",
                                          fontnameasian="Liberation Mono", fontsizeasian="10pt",
                                          fontweightasian="bold",
                                          fontnamecomplex="Liberation Mono", fontsizecomplex="10pt",
                                          fontweightcomplex="bold"))
doc.automaticstyles.addElement(mono_bold_style)

# --- Style: Sans-serif, large (different engineer) ---
sans_style = Style(name="SansPara", family="paragraph")
sans_style.addElement(ParagraphProperties(textalign="left"))
sans_style.addElement(TextProperties(fontname="Liberation Sans", fontsize="14pt",
                                     fontnameasian="Liberation Sans", fontsizeasian="14pt",
                                     fontnamecomplex="Liberation Sans", fontsizecomplex="14pt"))
doc.automaticstyles.addElement(sans_style)

# --- Style: Bold section label in sans context ---
sans_bold_style = Style(name="SansBold", family="paragraph")
sans_bold_style.addElement(ParagraphProperties(textalign="left"))
sans_bold_style.addElement(TextProperties(fontname="Liberation Sans", fontsize="14pt",
                                          fontweight="bold",
                                          fontnameasian="Liberation Sans", fontsizeasian="14pt",
                                          fontweightasian="bold",
                                          fontnamecomplex="Liberation Sans", fontsizecomplex="14pt",
                                          fontweightcomplex="bold"))
doc.automaticstyles.addElement(sans_bold_style)

# --- Style: Serif, correct size but CENTER-aligned (wrong alignment) ---
serif_center_style = Style(name="SerifCenter", family="paragraph")
serif_center_style.addElement(ParagraphProperties(textalign="center"))
serif_center_style.addElement(TextProperties(fontname="Liberation Serif", fontsize="12pt",
                                             fontnameasian="Liberation Serif", fontsizeasian="12pt",
                                             fontnamecomplex="Liberation Serif", fontsizecomplex="12pt"))
doc.automaticstyles.addElement(serif_center_style)

# --- Style: Bold section label in serif-center context ---
serif_center_bold_style = Style(name="SerifCenterBold", family="paragraph")
serif_center_bold_style.addElement(ParagraphProperties(textalign="center"))
serif_center_bold_style.addElement(TextProperties(fontname="Liberation Serif", fontsize="12pt",
                                                  fontweight="bold",
                                                  fontnameasian="Liberation Serif", fontsizeasian="12pt",
                                                  fontweightasian="bold",
                                                  fontnamecomplex="Liberation Serif", fontsizecomplex="12pt",
                                                  fontweightcomplex="bold"))
doc.automaticstyles.addElement(serif_center_bold_style)

# =====================================================================
# SECTION 1: Source Water Information (Liberation Mono 10pt, left)
# =====================================================================
doc.text.addElement(P(stylename=mono_bold_style, text="Source Water Information"))
doc.text.addElement(P(stylename=mono_style, text=""))

doc.text.addElement(P(stylename=mono_style,
    text="The City of Millbrook draws its drinking water from two sources: the "
         "Millbrook Reservoir, a surface water impoundment on Clear Creek with a "
         "storage capacity of 2.4 billion gallons, and the Cedar Valley Aquifer, a "
         "confined groundwater source that provides supplemental supply during peak "
         "summer demand."))

doc.text.addElement(P(stylename=mono_style,
    text="[REMOVE: Need to verify exact reservoir capacity with engineering -- Sarah K.]"))

doc.text.addElement(P(stylename=mono_style, text=""))

doc.text.addElement(P(stylename=mono_style,
    text="A Source Water Assessment completed by the North Carolina DEQ in 2022 "
         "determined that the Millbrook Reservoir has a moderate susceptibility to "
         "contamination due to agricultural land use and a retired landfill within "
         "the watershed protection area. The Cedar Valley Aquifer was assessed as "
         "having low susceptibility. The full assessment is available at the "
         "Millbrook Public Library or by contacting our office."))

doc.text.addElement(P(stylename=mono_style, text=""))

# =====================================================================
# SECTION 2: Water Treatment Process (Liberation Sans 14pt, left)
# =====================================================================
doc.text.addElement(P(stylename=sans_bold_style, text="Water Treatment Process"))
doc.text.addElement(P(stylename=sans_style, text=""))

doc.text.addElement(P(stylename=sans_style,
    text="Raw surface water from the Millbrook Reservoir undergoes a multi-barrier "
         "treatment process at the Clear Creek Water Treatment Plant (capacity: "
         "12 MGD). Treatment stages include coagulation with aluminum sulfate, "
         "flocculation, sedimentation, dual-media granular filtration, and primary "
         "disinfection with free chlorine."))

doc.text.addElement(P(stylename=sans_style,
    text="[REMOVE: Draft language, pending review by operations superintendent]"))

doc.text.addElement(P(stylename=sans_style, text=""))

doc.text.addElement(P(stylename=sans_style,
    text="Groundwater from the Cedar Valley Aquifer receives sodium hypochlorite "
         "disinfection and pH adjustment with sodium hydroxide at the Cedar Valley "
         "Pump Station before entering the distribution system. Orthophosphate is "
         "added at both facilities as a corrosion control measure to minimize lead "
         "and copper leaching from service lines and household plumbing."))

doc.text.addElement(P(stylename=sans_style,
    text="[REMOVE: Insert diagram reference for treatment schematic once graphics team finalizes]"))

doc.text.addElement(P(stylename=sans_style, text=""))

# =====================================================================
# SECTION 3: Violations & Explanations (Liberation Sans 14pt, left)
# =====================================================================
doc.text.addElement(P(stylename=sans_bold_style, text="Violations & Explanations"))
doc.text.addElement(P(stylename=sans_style, text=""))

doc.text.addElement(P(stylename=sans_style,
    text="During 2025, the Millbrook water system had one violation of EPA drinking "
         "water standards. Lead testing under the Lead and Copper Rule revealed a "
         "90th percentile value of 8.2 ppb at residential taps, which did not exceed "
         "the Action Level of 15 ppb. However, two individual sampling sites (Site 14 "
         "at 16.3 ppb and Site 27 at 18.5 ppb) returned results above the Action Level."))

doc.text.addElement(P(stylename=sans_style,
    text="In response, the City has accelerated its lead service line replacement "
         "program, increased orthophosphate dosing from 1.0 to 1.5 mg/L, and provided "
         "point-of-use filters to affected households. Public notification was issued "
         "within 30 days as required under 40 CFR 141.85."))

doc.text.addElement(P(stylename=sans_style,
    text="[REMOVE: Ask compliance team whether to include the individual site addresses]"))

doc.text.addElement(P(stylename=sans_style, text=""))

# =====================================================================
# SECTION 4: Health Information (Liberation Serif 12pt, CENTER - wrong)
# =====================================================================
doc.text.addElement(P(stylename=serif_center_bold_style, text="Health Information"))
doc.text.addElement(P(stylename=serif_center_style, text=""))

doc.text.addElement(P(stylename=serif_center_style,
    text="Some people may be more vulnerable to contaminants in drinking water than "
         "the general population. Immunocompromised persons such as persons with cancer "
         "undergoing chemotherapy, persons who have undergone organ transplants, people "
         "with HIV/AIDS or other immune system disorders, some elderly, and infants can "
         "be particularly at risk from infections. These people should seek advice about "
         "drinking water from their health care providers."))

doc.text.addElement(P(stylename=serif_center_style,
    text="[REMOVE: TODO check if this paragraph duplicates the lead-specific health language]"))

doc.text.addElement(P(stylename=serif_center_style, text=""))

doc.text.addElement(P(stylename=serif_center_style,
    text="Infants and young children are typically more vulnerable to lead in drinking "
         "water than the general population. It is possible that lead levels at your "
         "home may be higher than at other homes in the community as a result of "
         "materials used in your home's plumbing. If you are concerned about elevated "
         "lead levels in your home's water, you may wish to have your water tested. "
         "Flushing your tap for 30 seconds to 2 minutes before using water for "
         "drinking or cooking can reduce lead concentrations. Additional information "
         "is available from the EPA Safe Drinking Water Hotline at 1-800-426-4791."))

doc.text.addElement(P(stylename=serif_center_style, text=""))

# =====================================================================
# SECTION 5: How to Participate (Liberation Serif 12pt, CENTER - wrong)
# =====================================================================
doc.text.addElement(P(stylename=serif_center_bold_style, text="How to Participate"))
doc.text.addElement(P(stylename=serif_center_style, text=""))

doc.text.addElement(P(stylename=serif_center_style,
    text="The Millbrook Utility Board meets on the second Tuesday of each month at "
         "6:30 PM in the Millbrook Municipal Building, Council Chambers (100 Main "
         "Street). Meetings are open to the public. The annual water quality report "
         "is presented each July. Residents may submit written comments or questions "
         "to the Water Quality Division at any time."))

doc.text.addElement(P(stylename=serif_center_style,
    text="[REMOVE: Confirm meeting room number with front desk -- is it still Room 204?]"))

doc.text.addElement(P(stylename=serif_center_style, text=""))

# =====================================================================
# SECTION 6: Contact Information (Liberation Serif 12pt, CENTER - wrong)
# =====================================================================
doc.text.addElement(P(stylename=serif_center_bold_style, text="Contact Information"))
doc.text.addElement(P(stylename=serif_center_style, text=""))

doc.text.addElement(P(stylename=serif_center_style,
    text="City of Millbrook Water Quality Division"))
doc.text.addElement(P(stylename=serif_center_style,
    text="100 Main Street, Suite 210"))
doc.text.addElement(P(stylename=serif_center_style,
    text="Millbrook, NC 27028"))
doc.text.addElement(P(stylename=serif_center_style, text=""))
doc.text.addElement(P(stylename=serif_center_style,
    text="Water Quality Hotline: (336) 555-0147"))
doc.text.addElement(P(stylename=serif_center_style,
    text="Email: waterquality@millbrooknc.gov"))
doc.text.addElement(P(stylename=serif_center_style,
    text="Website: www.millbrooknc.gov/water"))
doc.text.addElement(P(stylename=serif_center_style, text=""))
doc.text.addElement(P(stylename=serif_center_style,
    text="Program Manager: Jordan Ellis, PE"))
doc.text.addElement(P(stylename=serif_center_style,
    text="Office Hours: Monday-Friday, 8:00 AM - 5:00 PM"))

doc.save("/home/ga/Desktop/ccr_narrative_sections.odt")
print("Created ccr_narrative_sections.odt")
PYEOF

# ------------------------------------------------------------------
# Create the EPA formatting requirements guide (plain text)
# ------------------------------------------------------------------
cat > /home/ga/Desktop/epa_ccr_format_guide.txt << 'GUIDEEOF'
EPA Consumer Confidence Report -- Formatting Requirements
==========================================================

PAGE LAYOUT
  Paper size: Letter (8.5 x 11 inches)
  Margins: 1 inch on all sides
  Body font: 12pt serif (Liberation Serif or Times New Roman)
  Body alignment: Justified

COVER PAGE
  Line 1: "City of Millbrook Department of Public Utilities" -- 18pt, bold, centered
  Line 2: "Annual Water Quality Report" -- 16pt, centered
  Line 3: "Calendar Year 2025" -- 14pt, centered
  Insert a page break after the cover page.

TABLE OF CONTENTS
  Insert an auto-generated Table of Contents after the cover page.
  Insert a page break after the Table of Contents.

SECTION HEADINGS
  Apply Heading 1 style to each main section heading.
  Required sections in this order:
    1. Source Water Information
    2. Water Treatment Process
    3. Detected Contaminants
    4. Violations & Explanations
    5. Health Information
    6. How to Participate
    7. Contact Information

DETECTED CONTAMINANTS TABLE
  Create a table with 7 columns:
    Contaminant | Unit | MCL | MCLG | Level Detected | Range | Violation
  Include one data row per contaminant tested (8 contaminants total).
  The header row must use bold text.
  Any row where the Violation column reads "Yes" must be formatted
  in bold italic (the entire row).

FOOTER
  Left side: "City of Millbrook -- CCR 2025"
  Right side: Page number
  Footer should appear on all pages after the cover page.

CLEANUP
  Remove all internal draft notes marked with [REMOVE] before
  final submission. These notes appear in square brackets and
  begin with the word REMOVE.
  Ensure consistent font throughout the body text.

Save the completed document as: millbrook_ccr_2025.odt
GUIDEEOF

chown ga:ga /home/ga/Desktop/lab_results_2025.odt
chown ga:ga /home/ga/Desktop/ccr_narrative_sections.odt
chown ga:ga /home/ga/Desktop/epa_ccr_format_guide.txt
chmod 0644 /home/ga/Desktop/epa_ccr_format_guide.txt

# ------------------------------------------------------------------
# Launch Calligra Words blank (agent must create the output document)
# ------------------------------------------------------------------
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords >/tmp/calligra_words_task.log 2>&1 < /dev/null &"
sleep 5

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
