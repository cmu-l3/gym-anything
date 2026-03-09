#!/bin/bash
# set -euo pipefail

echo "=== Setting up Contact Consolidation Task ==="

source /workspace/scripts/task_utils.sh

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Create first data source: EventPlatform1 Export (clean format but mixed case)
cat > /home/ga/Documents/platform1.csv << 'EOF'
FirstName,LastName,Email,Phone
John,Smith,john.smith@email.com,(555) 123-4567
SARAH,JOHNSON,sarah.j@email.com,555-234-5678
alice,brown,alice.brown@email.com,5553456789
Michael,Davis,michael.davis@email.com,(555) 456-7890
Emma,Wilson,emma.w@email.com,555-567-8901
Robert,JONES,robert.jones@email.com,(555) 678-9012
lisa,Garcia,lisa.garcia@email.com,555-789-0123
David,Miller,david.m@email.com,(555) 890-1234
JENNIFER,Martinez,jennifer.martinez@email.com,555-901-2345
james,Anderson,james.anderson@email.com,
maria,Taylor,maria.taylor@email.com,(555) 012-3456
Christopher,Thomas,chris.thomas@email.com,555-123-4567
amanda,Jackson,amanda.j@email.com,
matthew,White,matthew.white@email.com,(555) 234-5678
Jessica,Harris,jessica.harris@email.com,555-345-6789
daniel,Martin,daniel.martin@email.com,
emily,Thompson,emily.t@email.com,(555) 456-7890
Ryan,Garcia,ryan.garcia@email.com,555-567-8901
nicole,Robinson,nicole.r@email.com,
kevin,Clark,kevin.clark@email.com,(555) 678-9012
Lauren,Rodriguez,lauren.rodriguez@email.com,555-789-0123
brandon,Lewis,brandon.lewis@email.com,
stephanie,Lee,stephanie.lee@email.com,(555) 890-1234
justin,Walker,justin.walker@email.com,555-901-2345
Rachel,Hall,rachel.hall@email.com,
tyler,Allen,tyler.allen@email.com,(555) 012-3456
Megan,Young,megan.young@email.com,555-123-4567
Aaron,Hernandez,aaron.h@email.com,
Brittany,King,brittany.king@email.com,(555) 234-5678
Jonathan,Wright,jonathan.wright@email.com,555-345-6789
Samantha,Lopez,samantha.lopez@email.com,
Andrew,Hill,andrew.hill@email.com,(555) 456-7890
Ashley,Scott,ashley.scott@email.com,555-567-8901
Joshua,Green,joshua.green@email.com,
Melissa,Adams,melissa.adams@email.com,(555) 678-9012
Brandon,Baker,brandon.baker@email.com,555-789-0123
Amanda,Nelson,amanda.nelson@email.com,
Kyle,Carter,kyle.carter@email.com,(555) 890-1234
Christina,Mitchell,christina.m@email.com,555-901-2345
Travis,Perez,travis.perez@email.com,
EOF

# Create second data source: EventPlatform2 Export (different format, some duplicates)
cat > /home/ga/Documents/platform2.csv << 'EOF'
FullName,EmailAddress,PhoneNumber
John Smith,JOHN.SMITH@EMAIL.COM,555-123-4567
Sarah Johnson,Sarah.J@Email.com,5552345678
Emma Wilson,emma.w@email.com,(555) 567-8901
Robert Jones,Robert.Jones@Email.COM,555.678.9012
David Miller,david.m@email.com,555 890 1234
Christopher Thomas,CHRIS.THOMAS@EMAIL.COM,555.123.4567
Daniel Martin,daniel.martin@email.com,
Rachel Hall,RACHEL.HALL@EMAIL.COM,(555) 012-3456
Samantha Lopez,samantha.lopez@email.com,555-345-6789
Kyle Carter,kyle.carter@email.com,555 890 1234
Nathan Brooks,nathan.brooks@email.com,(555) 111-2222
Olivia Parker,olivia.parker@email.com,555-222-3333
Ethan Cooper,ethan.cooper@email.com,
Sophia Reed,sophia.reed@email.com,(555) 333-4444
Mason Bailey,mason.bailey@email.com,555-444-5555
Isabella Foster,isabella.foster@email.com,
Lucas Gray,lucas.gray@email.com,(555) 555-6666
Ava James,ava.james@email.com,555-666-7777
Noah Bennett,noah.bennett@email.com,
Mia Wood,mia.wood@email.com,(555) 777-8888
Liam Barnes,liam.barnes@email.com,555-888-9999
Charlotte Ross,charlotte.ross@email.com,
Oliver Henderson,oliver.henderson@email.com,(555) 999-0000
Amelia Coleman,amelia.coleman@email.com,555-000-1111
Elijah Jenkins,elijah.jenkins@email.com,
Grace Perry,grace.perry@email.com,(555) 111-3333
Logan Powell,logan.powell@email.com,555-222-4444
Chloe Long,chloe.long@email.com,
Jackson Patterson,jackson.patterson@email.com,(555) 333-5555
Lily Hughes,lily.hughes@email.com,555-444-6666
Aiden Flores,aiden.flores@email.com,
Zoe Washington,zoe.washington@email.com,(555) 555-7777
Carter Butler,carter.butler@email.com,555-666-8888
Ella Simmons,ella.simmons@email.com,
Gabriel Foster,gabriel.foster@email.com,(555) 777-9999
EOF

# Create third data source: Manual Entry (messy with display names, typos)
cat > /home/ga/Documents/manual.csv << 'EOF'
Name,Email,Phone
 John Smith ,John Smith <john.smith@email.com>,(555)123-4567
SARAH JOHNSON,<sarah.j@email.com>,
alice brown,Alice Brown <alice.brown@email.com>,555 345 6789
 Emma Wilson,emma.w@email.com,5555678901
christopher thomas,Chris Thomas <chris.thomas@email.com>,
melissa adams,MELISSA.ADAMS@EMAIL.COM,555-678-9012
TRAVIS PEREZ,travis.perez@email.com,(555) 901-2345
 sophia reed ,Sophia Reed <sophia.reed@email.com>,555-333-4444
mason bailey,mason.bailey@email.com,
 NATHAN BROOKS,nathan.brooks@email.com,555 111 2222
olivia parker, olivia.parker@email.com ,555-222-3333
LUCAS GRAY,Lucas.Gray@Email.Com,555.555.6666
ava james,ava.james@email.com,
MIA WOOD,Mia Wood <mia.wood@email.com>,(555) 777-8888
charlotte ross,charlotte.ross@email.com,555-000-1111
 Grace Perry,grace.perry@email.com,
jackson patterson,Jackson Patterson <jackson.patterson@email.com>,555-333-5555
ella simmons, ELLA.SIMMONS@EMAIL.COM,
Victoria Cruz,victoria.cruz@email.com,(555) 123-9999
Henry Diaz,henry.diaz@email.com,555-234-0000
Penelope Myers,penelope.myers@email.com,
Alexander Ford,alexander.ford@email.com,(555) 345-1111
Scarlett Wells,scarlett.wells@email.com,555-456-2222
Sebastian Stone,sebastian.stone@email.com,
Aria Tucker,aria.tucker@email.com,
EOF

# Set permissions
chown ga:ga /home/ga/Documents/platform1.csv
chown ga:ga /home/ga/Documents/platform2.csv
chown ga:ga /home/ga/Documents/manual.csv

echo "✅ Created 3 messy data source files"

# Create a combined workbook with Python
echo "Creating multi-sheet workbook..."
python3 << 'PYEOF'
import csv
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

def create_sheet_from_csv(csv_path, sheet_name):
    """Create table from CSV file"""
    table = Table(name=sheet_name)
    
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        for row_data in reader:
            row = TableRow()
            for cell_value in row_data:
                cell = TableCell()
                p = P(text=str(cell_value))
                cell.addElement(p)
                row.addElement(cell)
            table.addElement(row)
    
    return table

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add three sheets
sheet1 = create_sheet_from_csv('/home/ga/Documents/platform1.csv', 'EventPlatform1_Export')
sheet2 = create_sheet_from_csv('/home/ga/Documents/platform2.csv', 'EventPlatform2_Export')
sheet3 = create_sheet_from_csv('/home/ga/Documents/manual.csv', 'ManualEntry_SignUp')

doc.spreadsheet.addElement(sheet1)
doc.spreadsheet.addElement(sheet2)
doc.spreadsheet.addElement(sheet3)

# Save
doc.save('/home/ga/Documents/contacts_messy.ods')
print("✅ Created multi-sheet workbook")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/contacts_messy.ods
chmod 666 /home/ga/Documents/contacts_messy.ods

# Launch LibreOffice Calc with the workbook
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/contacts_messy.ods > /tmp/calc_contacts.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_contacts.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Contact Consolidation Task Setup Complete ==="
echo ""
echo "📋 Current state:"
echo "  - Sheet 1: EventPlatform1_Export (40 entries)"
echo "  - Sheet 2: EventPlatform2_Export (35 entries)"
echo "  - Sheet 3: ManualEntry_SignUp (25 entries)"
echo "  - Total: ~100 raw entries with duplicates and formatting issues"
echo ""
echo "🎯 Your task:"
echo "  1. Create new sheet: MasterContactList"
echo "  2. Consolidate all contacts (deduplicate, standardize)"
echo "  3. Format: FirstName | LastName | Email | Phone | Source | Status"
echo "  4. Standardize emails (lowercase, no display names)"
echo "  5. Standardize names (Title Case)"
echo "  6. Flag incomplete records (NEEDS_INFO vs VERIFIED)"
echo "  7. Add summary statistics at top"
echo ""
echo "💡 Tips:"
echo "  - Use COUNTIF to find duplicates"
echo "  - Use TRIM(), LOWER(), PROPER() for standardization"
echo "  - Expected final count: ~60-65 unique contacts"