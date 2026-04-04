#!/bin/bash
# Setup for standardize_journal_abbreviations task
# 1. Seeds library with classic papers
# 2. Modifies specific papers to have ABBREVIATED journal titles (the "messy" state)
# 3. Restarts Zotero

echo "=== Setting up standardize_journal_abbreviations task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers ───────────────────────────────────────────────────────────
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode classic > /tmp/seed_output.txt 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: seeding failed"
    cat /tmp/seed_output.txt
    exit 1
fi

# ── 3. Modify DB to create "messy" state (Abbreviations) ─────────────────────
# Field ID 38 is Publication Title in Zotero 7 schema context
# We need to find the Value ID for the publication field of specific items and update it

echo "Applying abbreviations to create starting state..."
sqlite3 "$DB" << 'EOF'
-- Update Einstein (1905)
UPDATE itemDataValues 
SET value = 'Ann. Phys.' 
WHERE valueID IN (
    SELECT d.valueID 
    FROM items i 
    JOIN itemData d ON i.itemID = d.itemID 
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 38 -- Publication Title
    AND i.itemID IN (
        SELECT i.itemID FROM items i 
        JOIN itemData d ON i.itemID = d.itemID 
        JOIN itemDataValues v ON d.valueID = v.valueID 
        WHERE d.fieldID = 1 AND v.value LIKE 'On the Electrodynamics of Moving Bodies%'
    )
);

-- Update McCarthy (1960)
UPDATE itemDataValues 
SET value = 'Comm. ACM' 
WHERE valueID IN (
    SELECT d.valueID 
    FROM items i 
    JOIN itemData d ON i.itemID = d.itemID 
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 38 
    AND i.itemID IN (
        SELECT i.itemID FROM items i 
        JOIN itemData d ON i.itemID = d.itemID 
        JOIN itemDataValues v ON d.valueID = v.valueID 
        WHERE d.fieldID = 1 AND v.value LIKE 'Recursive Functions of Symbolic Expressions%'
    )
);

-- Update Dijkstra (1959)
UPDATE itemDataValues 
SET value = 'Numer. Math.' 
WHERE valueID IN (
    SELECT d.valueID 
    FROM items i 
    JOIN itemData d ON i.itemID = d.itemID 
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 38 
    AND i.itemID IN (
        SELECT i.itemID FROM items i 
        JOIN itemData d ON i.itemID = d.itemID 
        JOIN itemDataValues v ON d.valueID = v.valueID 
        WHERE d.fieldID = 1 AND v.value LIKE 'A Note on Two Problems in Connexion with Graphs%'
    )
);

-- Update Shannon (1948)
UPDATE itemDataValues 
SET value = 'Bell Syst. Tech. J.' 
WHERE valueID IN (
    SELECT d.valueID 
    FROM items i 
    JOIN itemData d ON i.itemID = d.itemID 
    JOIN itemDataValues v ON d.valueID = v.valueID
    WHERE d.fieldID = 38 
    AND i.itemID IN (
        SELECT i.itemID FROM items i 
        JOIN itemData d ON i.itemID = d.itemID 
        JOIN itemDataValues v ON d.valueID = v.valueID 
        WHERE d.fieldID = 1 AND v.value LIKE 'A Mathematical Theory of Communication%'
    )
);
EOF

# Record timestamp
date +%s > /tmp/task_start_time

# ── 4. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# Wait for Zotero window
echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "  Window found after ${i}s"
        break
    fi
    sleep 1
done
sleep 3

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 2

# ── 5. Initial Screenshot ─────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete: standardize_journal_abbreviations ==="