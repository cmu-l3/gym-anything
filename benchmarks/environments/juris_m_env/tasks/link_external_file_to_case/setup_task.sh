#!/bin/bash
echo "=== Setting up link_external_file_to_case task ==="
source /workspace/scripts/task_utils.sh

# 1. Create the external file structure
echo "Creating dummy case file..."
mkdir -p /home/ga/Documents/CaseFiles/Project_X
cat > /home/ga/Documents/CaseFiles/Project_X/Miranda_Opinion.pdf << EOF
%PDF-1.4
%
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 55 >>
stream
BT /F1 24 Tf 100 700 Td (Opinion of the Court: Miranda v. Arizona) Tj ET
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000010 00000 n 
0000000060 00000 n 
0000000117 00000 n 
0000000204 00000 n 
trailer
<< /Size 5 /Root 1 0 R >>
startxref
309
%%EOF
EOF
chown -R ga:ga /home/ga/Documents/CaseFiles

# 2. Locate Database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

# 3. Stop Jurism for DB manipulation
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 4. Ensure Library has data
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Injecting legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null
fi

# 5. Clean state: Remove any existing attachments/children of Miranda v. Arizona
echo "Cleaning existing attachments for Miranda v. Arizona..."
python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()

# Find Miranda item ID (fieldID=58 is caseName, fieldID=1 is title)
c.execute('''
    SELECT items.itemID FROM items 
    JOIN itemData ON items.itemID = itemData.itemID 
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
    WHERE fieldID IN (1, 58) AND value LIKE \"%Miranda%Arizona%\"
    LIMIT 1
''')
row = c.fetchone()
if row:
    parent_id = row[0]
    print(f'Found Miranda v. Arizona ID: {parent_id}')
    
    # Find children (attachments/notes)
    c.execute('SELECT itemID FROM itemAttachments WHERE parentItemID=?', (parent_id,))
    children = [r[0] for r in c.fetchall()]
    
    for child_id in children:
        print(f'Deleting child item {child_id}')
        c.execute('DELETE FROM itemAttachments WHERE itemID=?', (child_id,))
        c.execute('DELETE FROM items WHERE itemID=?', (child_id,))
        # Also cleanup itemData if any exists for the attachment
        c.execute('DELETE FROM itemData WHERE itemID=?', (child_id,))
    
    conn.commit()
else:
    print('WARNING: Miranda v. Arizona not found in DB')

conn.close()
"

# Remove db journal to prevent locks
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# 6. Record task start time
date +%s > /tmp/task_start_timestamp

# 7. Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# 8. Wait and maximize
wait_and_dismiss_jurism_alerts 45
ensure_jurism_running

# 9. Initial Screenshot
take_screenshot /tmp/link_task_start.png

echo "=== Setup Complete ==="
echo "Target File: /home/ga/Documents/CaseFiles/Project_X/Miranda_Opinion.pdf"