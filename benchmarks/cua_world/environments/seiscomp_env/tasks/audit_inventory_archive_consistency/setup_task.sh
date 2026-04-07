#!/bin/bash
echo "=== Setting up audit_inventory_archive_consistency task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure SeisComP services are ready ───────────────────────────────────
ensure_scmaster_running
sleep 2

# ─── 2. Generate Random Discrepancies ────────────────────────────────────────
# Known valid GE stations in the base env: TOLI, GSI, KWP, SANI, BKB
STATIONS=("TOLI" "GSI" "KWP" "SANI" "BKB")
RANDOM_IDX=$((RANDOM % 5))
MISSING_STA=${STATIONS[$RANDOM_IDX]}

# Generate a random orphan station name (e.g., Z01 to Z99)
ORPHAN_STA=$(printf "Z%02d" $((RANDOM % 99 + 1)))

# Securely save the ground truth (hidden from the 'ga' user)
echo "Missing: $MISSING_STA" > /tmp/.task_truth
echo "Orphan: $ORPHAN_STA" >> /tmp/.task_truth
chmod 600 /tmp/.task_truth

echo "Discrepancy generated (Hidden from agent). Missing: $MISSING_STA, Orphan: $ORPHAN_STA"

# ─── 3. Manipulate the SDS Archive ───────────────────────────────────────────
ARCHIVE_DIR="/home/ga/seiscomp/var/lib/archive/2024/GE"

# Ensure base archive directory exists
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo "ERROR: Base archive directory $ARCHIVE_DIR not found!"
    exit 1
fi

# Remove the 'Missing' station from the archive
rm -rf "$ARCHIVE_DIR/$MISSING_STA"

# Create the 'Orphan' station by duplicating an existing one
SRC_STA="TOLI"
if [ "$MISSING_STA" == "TOLI" ]; then
    SRC_STA="GSI" # Fallback if TOLI is the missing one
fi

cp -r "$ARCHIVE_DIR/$SRC_STA" "$ARCHIVE_DIR/$ORPHAN_STA"

# Rename files inside the orphan station directory to match standard SDS format
for cha_dir in "$ARCHIVE_DIR/$ORPHAN_STA"/*.D; do
    [ -d "$cha_dir" ] || continue
    for f in "$cha_dir"/*; do
        [ -f "$f" ] || continue
        # Replace the station code in the filename
        newname=$(echo "$f" | sed "s/\.${SRC_STA}\./\.${ORPHAN_STA}\./g")
        mv "$f" "$newname"
    done
done

# Ensure correct permissions
chown -R ga:ga "$ARCHIVE_DIR"

# ─── 4. Prepare User Environment ─────────────────────────────────────────────
# Start a terminal maximized so the agent can immediately start exploring
su - ga -c "DISPLAY=:1 gnome-terminal --maximize" &
sleep 3

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="