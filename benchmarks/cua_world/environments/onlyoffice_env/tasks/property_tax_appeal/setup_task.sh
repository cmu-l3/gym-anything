#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Property Tax Appeal Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
SPREADSHEET_DIR="/home/ga/Documents/Spreadsheets"
TEXTDOC_DIR="/home/ga/Documents/TextDocuments"
sudo -u ga mkdir -p "$SPREADSHEET_DIR"
sudo -u ga mkdir -p "$TEXTDOC_DIR"

# Create detailed instruction file on Desktop
cat > /home/ga/Desktop/PROPERTY_TAX_APPEAL_INSTRUCTIONS.txt << 'EOF'
================================================================================
                    PROPERTY TAX ASSESSMENT APPEAL TASK
================================================================================

URGENT SITUATION:
You just received your annual property tax reassessment. The county assessor
has valued your home at $425,000 - a shocking 38% increase from last year's
$308,000 assessment! Your monthly mortgage payment will jump by $340.

You have NOT made any improvements to the home (same old kitchen, dated 
bathrooms). Your neighbors' similar homes are assessed much lower. This 
appears to be an error.

YOU HAVE 21 DAYS TO APPEAL. You need to prepare:
1. A property comparison analysis (spreadsheet)
2. A formal appeal letter to the County Board of Equalization

================================================================================
TASK 1: CREATE PROPERTY COMPARISON SPREADSHEET
================================================================================

File: /home/ga/Documents/Spreadsheets/property_comparison.xlsx

Create a table comparing your home to 4 similar properties:

Header Row (Row 1):
| Property Address | Lot Size (acres) | Finished Sq Ft | Bedrooms | Bathrooms | Year Built | Assessed Value | $/Sq Ft |

YOUR HOME (Row 2):
  Address: 123 Oak Street
  Lot Size: 0.28
  Square Feet: 1850
  Bedrooms: 3
  Bathrooms: 2.0
  Year Built: 1978
  Assessed Value: 425000
  $/Sq Ft: [FORMULA: =G2/C2 (Assessed Value / Square Feet)]

COMPARABLE PROPERTY #1 (Row 3):
  Address: 118 Oak Street
  Lot Size: 0.25
  Square Feet: 1820
  Bedrooms: 3
  Bathrooms: 2.0
  Year Built: 1975
  Assessed Value: 298000
  $/Sq Ft: [FORMULA: =G3/C3]

COMPARABLE PROPERTY #2 (Row 4):
  Address: 207 Maple Avenue
  Lot Size: 0.30
  Square Feet: 1900
  Bedrooms: 3
  Bathrooms: 2.0
  Year Built: 1982
  Assessed Value: 312000
  $/Sq Ft: [FORMULA: =G4/C4]

COMPARABLE PROPERTY #3 (Row 5):
  Address: 145 Oak Street
  Lot Size: 0.27
  Square Feet: 1875
  Bedrooms: 3
  Bathrooms: 2.5
  Year Built: 1980
  Assessed Value: 305000
  $/Sq Ft: [FORMULA: =G5/C5]

COMPARABLE PROPERTY #4 (Row 6):
  Address: 89 Cedar Lane
  Lot Size: 0.29
  Square Feet: 1840
  Bedrooms: 3
  Bathrooms: 2.0
  Year Built: 1976
  Assessed Value: 294000
  $/Sq Ft: [FORMULA: =G6/C6]

SUMMARY CALCULATIONS (Start at Row 8):

Row 8: Average $/Sq Ft (comparables only)
  Column A: "Average $/Sq Ft (comparables):"
  Column B: [FORMULA: =AVERAGE(H3:H6)]

Row 9: Fair Assessed Value for Your Home
  Column A: "Fair Assessed Value for Your Home:"
  Column B: [FORMULA: =C2*B8 (your sq ft × average $/sq ft)]

Row 10: Over-Assessment Amount
  Column A: "Over-Assessment Amount:"
  Column B: [FORMULA: =G2-B9 (your assessment - fair value)]

Row 11: Over-Assessment Percentage
  Column A: "Over-Assessment Percentage:"
  Column B: [FORMULA: =(B10/B9)*100]

FORMATTING REQUIREMENTS:
- Bold the header row (Row 1)
- Format columns with dollar amounts (Column G) as Currency ($)
- Format the percentage (B11) with 1 decimal place and % symbol
- All $/Sq Ft should show as numbers (no need for currency format)
- Use FORMULAS, not hardcoded numbers for all calculations

================================================================================
TASK 2: CREATE FORMAL APPEAL LETTER
================================================================================

File: /home/ga/Documents/TextDocuments/tax_appeal_letter.docx

Create a formal business letter with this structure:

[Your Name - use "Jordan Smith"]
123 Oak Street
Riverside County, State 12345

[Today's Date]

Riverside County Board of Equalization
County Assessor's Office
456 Government Plaza
County Seat, State 12345

RE: Property Tax Assessment Appeal for Parcel #45-12-089-234
    Property Address: 123 Oak Street

Dear Board Members:

[PARAGRAPH 1: State your purpose]
Write a paragraph that:
- States you are writing to formally appeal your 2025 property tax assessment
- References parcel number: 45-12-089-234
- Mentions current assessed value: $425,000
- Expresses belief that this is excessive and not reflective of fair market value

[PARAGRAPH 2: Explain your methodology]
Write a paragraph that:
- Explains you analyzed 4 comparable properties within 3 blocks
- Notes all were built between 1975-1982
- Mentions all are 3BR/2-2.5BA homes
- States similar lot sizes (0.25-0.30 acres)
- Notes similar square footage (1,820-1,900 sq ft)

[PARAGRAPH 3: Present your findings]
Write a paragraph that:
- States comparable properties assessed at $294,000-$312,000
- Mentions average assessment of approximately $302,000
- Notes this equates to approximately $164/sq ft
- Contrasts with your assessment of $230/sq ft
- States this represents approximately 38% over-assessment
- Mentions excess amount of approximately $123,000

[PARAGRAPH 4: Note no improvements & request action]
Write a paragraph that:
- States no improvements have been made to the property
- Notes property condition is unchanged from prior assessment
- Requests reassessment to fair market value consistent with neighborhood
- Suggests fair value around $303,000 based on analysis

[CLOSING PARAGRAPH: Professional tone]
Write a paragraph that:
- Acknowledges the difficult job of the assessor's office
- Expresses belief that this discrepancy is likely an error
- Respectfully requests review and adjustment
- States availability to provide additional information if needed
- Thanks them for their consideration

Sincerely,

Jordan Smith
Phone: 555-123-4567
Email: j.smith@email.com

Enclosure: Comparable Property Analysis

FORMATTING REQUIREMENTS:
- Use proper business letter format (sender address, date, recipient address)
- 1-inch margins (default)
- 11 or 12-point font (Times New Roman, Arial, or Calibri)
- Single-spaced with blank lines between paragraphs
- Professional, respectful tone throughout
- Clear RE: (subject) line with parcel number

================================================================================
STEPS TO COMPLETE:
================================================================================

1. Open ONLYOFFICE Spreadsheet Editor (from Desktop or Applications menu)
2. Create the property comparison table with all data
3. Enter formulas for all $/Sq Ft calculations (column H)
4. Enter summary formulas (rows 8-11)
5. Bold the header row
6. Format currency values appropriately
7. Save as: /home/ga/Documents/Spreadsheets/property_comparison.xlsx
8. (Use Ctrl+S to save)

9. Open ONLYOFFICE Document Editor (from Desktop or Applications menu)
10. Create the appeal letter following the structure above
11. Use proper business letter formatting
12. Write professional, complete paragraphs for each section
13. Reference the data from your spreadsheet analysis
14. Maintain respectful, professional tone throughout
15. Save as: /home/ga/Documents/TextDocuments/tax_appeal_letter.docx
16. (Use Ctrl+S to save)

================================================================================
DEADLINE: Complete both documents to submit your appeal on time!
================================================================================
EOF

chown ga:ga /home/ga/Desktop/PROPERTY_TAX_APPEAL_INSTRUCTIONS.txt

echo "✅ Instructions created at: /home/ga/Desktop/PROPERTY_TAX_APPEAL_INSTRUCTIONS.txt"

# We don't pre-launch ONLYOFFICE - let the agent choose which application to start first
# This tests their ability to navigate and use multiple applications

echo "=== Property Tax Appeal Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "  Create a property tax assessment appeal package with:"
echo "    1. Spreadsheet: property_comparison.xlsx (with formulas)"
echo "    2. Letter: tax_appeal_letter.docx (formal business format)"
echo ""
echo "📝 Detailed instructions available at:"
echo "    /home/ga/Desktop/PROPERTY_TAX_APPEAL_INSTRUCTIONS.txt"
echo ""
echo "⏰ Agent should complete both documents and save them"
echo ""