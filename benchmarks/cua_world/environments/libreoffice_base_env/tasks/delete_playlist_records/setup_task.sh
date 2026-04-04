#!/bin/bash
echo "=== Setting up Delete Playlist Records Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create a temporary copy of the ODB script to count initial records
# We extract just the script file from the ODB zip
echo "Analyzing initial database state..."
mkdir -p /tmp/initial_analysis
unzip -p /opt/libreoffice_base_samples/chinook.odb database/script > /tmp/initial_analysis/script

# Count target records (PlaylistId=17)
# Note: HSQLDB script format uses: INSERT INTO "Table" VALUES(...)
INITIAL_PT_COUNT=$(grep -c 'INSERT INTO PUBLIC."PlaylistTrack" VALUES(17,' /tmp/initial_analysis/script || echo "0")
INITIAL_PL_COUNT=$(grep -c 'INSERT INTO PUBLIC."Playlist" VALUES(17,' /tmp/initial_analysis/script || echo "0")
TOTAL_PL_COUNT=$(grep -c 'INSERT INTO PUBLIC."Playlist" VALUES(' /tmp/initial_analysis/script || echo "0")

# Save initial counts for export/verification
cat > /tmp/initial_state.json << EOF
{
    "target_playlist_tracks": $INITIAL_PT_COUNT,
    "target_playlist_record": $INITIAL_PL_COUNT,
    "total_playlists": $TOTAL_PL_COUNT
}
EOF

echo "Initial state: Playlist 17 has $INITIAL_PT_COUNT tracks. Total playlists: $TOTAL_PL_COUNT."
rm -rf /tmp/initial_analysis

# Setup LibreOffice Base (Kill existing, restore clean ODB, launch, wait, maximize)
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="