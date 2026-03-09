#!/bin/bash
set -e
echo "=== Setting up fix_metadata_errors task ==="

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Zotero is stopped to manipulate DB safely
pkill -f zotero || true
sleep 3

# 3. Seed the library with the standard paper set
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_log.txt 2>&1

# 4. Introduce Metadata Errors via SQLite
# We use sqlite3 to directly manipulate the Zotero database
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"
echo "Introducing metadata errors into $ZOTERO_DB..."

sqlite3 "$ZOTERO_DB" <<'SQL'
-- ERROR 1: Change Einstein's year from "1905" to "1095"
-- First, ensure "1095" exists in values
INSERT OR IGNORE INTO itemDataValues(value) VALUES('1095');
-- Update the link in itemData (fieldID 6 = Date)
UPDATE itemData SET valueID = (SELECT valueID FROM itemDataValues WHERE value = '1095')
WHERE fieldID = 6
  AND itemID = (
    SELECT d.itemID FROM itemData d
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 1 AND v.value LIKE '%Electrodynamics%Moving Bodies%'
  );

-- ERROR 2: Remove DOI from LeCun's "Deep Learning"
-- fieldID 59 = DOI
DELETE FROM itemData
WHERE fieldID = 59
  AND itemID = (
    SELECT d.itemID FROM itemData d
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 1 AND v.value = 'Deep Learning'
  );

-- ERROR 3: Change Turing's publication from "Mind" to "Mnd"
-- fieldID 38 = Publication Title
INSERT OR IGNORE INTO itemDataValues(value) VALUES('Mnd');
UPDATE itemData SET valueID = (SELECT valueID FROM itemDataValues WHERE value = 'Mnd')
WHERE fieldID = 38
  AND itemID = (
    SELECT d.itemID FROM itemData d
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 1 AND v.value LIKE '%Computing Machinery%Intelligence%'
  );
SQL

# 5. Record initial erroneous state (for verification debug)
echo "Recording initial state..."
sqlite3 "$ZOTERO_DB" <<'AUDIT' > /tmp/initial_state_audit.txt
SELECT 'Einstein Date:', v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID
WHERE d.fieldID=6 AND d.itemID=(SELECT d.itemID FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=1 AND v.value LIKE '%Electrodynamics%');

SELECT 'LeCun DOI count:', COUNT(*) FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID
WHERE d.fieldID=59 AND d.itemID=(SELECT d.itemID FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=1 AND v.value='Deep Learning');

SELECT 'Turing Pub:', v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID
WHERE d.fieldID=38 AND d.itemID=(SELECT d.itemID FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=1 AND v.value LIKE '%Computing Machinery%Intelligence%');
AUDIT

cat /tmp/initial_state_audit.txt

# 6. Start Zotero
echo "Starting Zotero..."
# Use setsid to detach from shell, redirect output to avoid hanging
sudo -u ga bash -c 'DISPLAY=:1 setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# 7. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Zotero"; then
        echo "✓ Zotero window detected"
        break
    fi
    sleep 1
done

# 8. Maximize and Focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 9. Initial Screenshot
echo "Capturing initial screenshot..."
sleep 1
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="