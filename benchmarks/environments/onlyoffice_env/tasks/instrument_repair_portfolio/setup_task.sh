#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Instrument Repair Portfolio Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw receipts file
RAW_FILE="$WORKSPACE_DIR/receipts_raw.txt"

cat > "$RAW_FILE" << 'RAWDATA'
INSTRUMENT REPAIR & MAINTENANCE RECORDS
========================================

INSTRUMENT PURCHASE INFORMATION:
- Cello "Antonio" (Italian, 1924): Purchased 2015 for $85,000
- Cello "Daily Player" (German, 2008): Purchased 2018 for $12,000  
- Violin (French, 1890): Purchased 2016 for $28,000
- Viola (Contemporary American, 2019): Purchased 2019 for $8,500

REPAIR/MAINTENANCE RECEIPTS:
----------------------------

Receipt #1:
Date: March 15, 2016
Instrument: Cello "Antonio"
Service: Complete setup, soundpost adjustment, new Larsen strings
Luthier: Maria's Fine Instruments, Boston
Cost: $450
Notes: First setup after purchase

Receipt #2:
Date: August 3, 2016  
Instrument: Violin
Service: Cleaned old varnish buildup, bridge reshaping
Luthier: Stringed Heritage Workshop
Cost: $220

Receipt #3:
Date: November 12, 2017
Instrument: Cello "Antonio"
Service: Crack repair on upper bout, retouch varnish
Luthier: Maria's Fine Instruments, Boston  
Cost: $1,850
Notes: Warranty work, humidity damage

Receipt #4:
Date: February 28, 2018
Instrument: Violin & Viola
Service: Bow rehairing (2 bows total)
Luthier: Stringed Heritage Workshop
Cost: $180 total ($90 each)

Receipt #5:
Date: June 10, 2018
Instrument: Cello "Daily Player"  
Service: Initial setup, bridge fitting, new strings
Luthier: Benson Brothers Lutherie (now closed)
Cost: $380

Receipt #6:
Date: December 1, 2018
Instrument: Cello "Antonio"
Service: Annual maintenance, soundpost check, string replacement
Luthier: Maria's Fine Instruments, Boston
Cost: $290

Receipt #7:
Date: May 22, 2019
Instrument: Viola
Service: Setup after purchase, peg fitting
Luthier: Contemporary Strings NYC
Cost: $200

Receipt #8:
Date: September 14, 2020
Instrument: Violin  
Service: Fingerboard replaning, new ebony nut
Luthier: Stringed Heritage Workshop
Cost: $650

Receipt #9:
Date: March 8, 2021
Instrument: Cello "Daily Player"
Service: Bridge replacement, new Thomastik strings
Luthier: Downtown Music Repair
Cost: $425

Receipt #10:
Date: October 19, 2022
Instrument: Cello "Antonio"
Service: Comprehensive insurance appraisal, full photos
Luthier: Maria's Fine Instruments, Boston
Cost: $350  
Notes: Appraised at $92,000 (appreciation noted)

Receipt #11:
Date: April 3, 2023
Instrument: Violin
Service: Soundpost crack repair, cleat installation
Luthier: Stringed Heritage Workshop
Cost: $980
Notes: Significant repair

Receipt #12:
Date: November 30, 2023
Instrument: Viola
Service: Bridge adjustment, new Dominant strings
Luthier: Contemporary Strings NYC
Cost: $175

UPCOMING MAINTENANCE NEEDED:
- Cello "Antonio": Bridge replacement recommended by Maria (no quote yet, est. $800-1200)
- Violin: Bow rehair needed before spring concerts (approx $95)

RAWDATA

chown ga:ga "$RAW_FILE"

echo "✅ Created receipts_raw.txt with 12 repair records"
echo "📍 Raw receipts file: $RAW_FILE"

# Create starter spreadsheet
OUTPUT_FILE="$WORKSPACE_DIR/instrument_portfolio.xlsx"

cat > /tmp/create_instrument_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Maintenance Log"

# Add title and instructions
ws['A1'] = "Instrument Maintenance Portfolio"
ws['A1'].font = Font(size=16, bold=True)
ws['A2'] = "Insurance Documentation - Organize data from receipts_raw.txt"
ws['A2'].font = Font(italic=True)

# Add hint for structure
ws['A4'] = "Suggested columns: Date | Instrument | Service/Repair | Luthier/Shop | Cost | Notes"
ws['A4'].font = Font(size=10, italic=True)

# Leave space for user to create their own structure
ws['A6'] = "Start organizing your data below..."

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_instrument_sheet.py
python3 /tmp/create_instrument_sheet.py "$OUTPUT_FILE"
chown ga:ga "$OUTPUT_FILE"

echo "✅ Starter spreadsheet created at: $OUTPUT_FILE"

# Launch ONLYOFFICE with the spreadsheet
echo "🚀 Launching ONLYOFFICE Calc..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$OUTPUT_FILE' > /tmp/onlyoffice_instrument_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_instrument_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Instrument Repair Portfolio Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "SCENARIO:"
echo "  You are a professional cellist who owns 4 string instruments."
echo "  Your insurance company needs comprehensive maintenance documentation."
echo "  You have 8 years of repair receipts to organize."
echo ""
echo "FILES PROVIDED:"
echo "  📄 $RAW_FILE"
echo "  📊 $OUTPUT_FILE (starter template)"
echo ""
echo "YOUR TASK:"
echo "  1. Review the repair records in receipts_raw.txt"
echo "  2. Create a structured maintenance log with columns:"
echo "     - Date, Instrument, Service/Repair, Luthier/Shop, Cost, Notes"
echo "  3. Enter all 12 service records from the file"
echo "  4. Use FORMULAS to calculate:"
echo "     - Total maintenance cost per instrument (SUM or SUMIF)"
echo "     - Total investment per instrument (Purchase + Maintenance)"
echo "  5. Visually flag upcoming maintenance items (highlighting/separate section)"
echo "  6. Create a SUMMARY section showing:"
echo "     - Instrument Name"
echo "     - Purchase Price"
echo "     - Total Maintenance Cost"
echo "     - Total Investment"
echo "     - Status"
echo "  7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "INSTRUMENTS & PURCHASE PRICES:"
echo "  - Cello 'Antonio': $85,000 (2015)"
echo "  - Cello 'Daily Player': $12,000 (2018)"
echo "  - Violin: $28,000 (2016)"
echo "  - Viola: $8,500 (2019)"
echo ""
echo "TIP: Open receipts_raw.txt in a text editor to reference while working"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"