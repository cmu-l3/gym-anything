#!/bin/bash
echo "=== Setting up assign_colored_tags task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Stop Zotero to modify DB safely
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed the library with papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 3. Inject Tags into the Database
# We use sqlite3 to manually tag items so they exist when the agent starts
echo "Injecting tags..."
sqlite3 "$DB_PATH" <<EOF
-- Ensure tags exist
INSERT OR IGNORE INTO tags (name) VALUES ('deep-learning');
INSERT OR IGNORE INTO tags (name) VALUES ('foundational');
INSERT OR IGNORE INTO tags (name) VALUES ('computer-vision');
INSERT OR IGNORE INTO tags (name) VALUES ('NLP');

-- Helper to link tags to items by title substring
-- deep-learning (7 items)
INSERT OR IGNORE INTO itemTags (itemID, tagID, type)
SELECT i.itemID, (SELECT tagID FROM tags WHERE name='deep-learning'), 0
FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID
WHERE d.fieldID=1 AND (
  v.value LIKE '%Attention%' OR v.value LIKE '%BERT%' OR v.value LIKE '%GPT%' 
  OR v.value LIKE '%ImageNet%' OR v.value LIKE '%Residual%' OR v.value LIKE '%Adversarial%' 
  OR v.value LIKE '%Deep Learning%'
);

-- foundational (5 items)
INSERT OR IGNORE INTO itemTags (itemID, tagID, type)
SELECT i.itemID, (SELECT tagID FROM tags WHERE name='foundational'), 0
FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID
WHERE d.fieldID=1 AND (
  v.value LIKE '%Turing%' OR v.value LIKE '%Electrodynamics%' OR v.value LIKE '%Communication%' 
  OR v.value LIKE '%Connexion%' OR v.value LIKE '%Nucleic%'
);

-- computer-vision (3 items)
INSERT OR IGNORE INTO itemTags (itemID, tagID, type)
SELECT i.itemID, (SELECT tagID FROM tags WHERE name='computer-vision'), 0
FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID
WHERE d.fieldID=1 AND (
  v.value LIKE '%ImageNet%' OR v.value LIKE '%Residual%' OR v.value LIKE '%Adversarial%'
);

-- NLP (3 items)
INSERT OR IGNORE INTO itemTags (itemID, tagID, type)
SELECT i.itemID, (SELECT tagID FROM tags WHERE name='NLP'), 0
FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID
WHERE d.fieldID=1 AND (
  v.value LIKE '%Attention%' OR v.value LIKE '%BERT%' OR v.value LIKE '%Few-Shot%'
);
EOF

# 4. Clear any existing color settings (Anti-gaming / clean slate)
echo "Clearing existing tag colors..."
sqlite3 "$DB_PATH" "DELETE FROM settings WHERE setting='tagColors';"

# 5. Record start state
date +%s > /tmp/task_start_time.txt
# Verify tags are present in DB
TAG_CHECK=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tags WHERE name IN ('deep-learning', 'foundational', 'computer-vision', 'NLP')")
echo "Initial target tags count: $TAG_CHECK" > /tmp/initial_tag_check.txt

# 6. Restart Zotero (Required for DB changes to load in UI)
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize and Focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="