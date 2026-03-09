#!/bin/bash
# Setup for correct_author_metadata task
# Seeds library and then deliberately corrupts specific author names

echo "=== Setting up correct_author_metadata task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers ───────────────────────────────────────────────────────────
echo "Seeding library..."
# Use mode 'all' to get the ML papers containing Vaswani, LeCun, Goodfellow
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1
SEED_EXIT=$?
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seeding failed"
    exit 1
fi

# ── 3. Corrupt Metadata ──────────────────────────────────────────────────────
echo "Introducing metadata errors..."

# Vaswani: Ashish -> A.
sqlite3 "$DB" "UPDATE creators SET firstName='A.' WHERE lastName='Vaswani';"

# LeCun: Yann LeCun -> y. Lecun
sqlite3 "$DB" "UPDATE creators SET firstName='y.', lastName='Lecun' WHERE lastName='LeCun';"

# Goodfellow: Ian J. -> Ian
sqlite3 "$DB" "UPDATE creators SET firstName='Ian' WHERE lastName='Goodfellow';"

# ── 4. Record Baseline & Start Time ──────────────────────────────────────────
# Record IDs for verification later
VASWANI_ID=$(sqlite3 "$DB" "SELECT creatorID FROM creators WHERE lastName='Vaswani';" || echo "0")
LECUN_ID=$(sqlite3 "$DB" "SELECT creatorID FROM creators WHERE lastName='Lecun';" || echo "0")
GOODFELLOW_ID=$(sqlite3 "$DB" "SELECT creatorID FROM creators WHERE lastName='Goodfellow';" || echo "0")

echo "Target Creator IDs: Vaswani=$VASWANI_ID, LeCun=$LECUN_ID, Goodfellow=$GOODFELLOW_ID"
echo "$VASWANI_ID" > /tmp/vaswani_id
echo "$LECUN_ID" > /tmp/lecun_id
echo "$GOODFELLOW_ID" > /tmp/goodfellow_id

# Record start time for anti-gaming (checking modification times)
date +%s > /tmp/task_start_time.txt

# ── 5. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
# Standard launch command for this environment
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "  Window found after ${i}s"
        break
    fi
    sleep 1
done
sleep 5

# Activate and maximize
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# ── 6. Initial Screenshot ────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete: correct_author_metadata ==="