#!/bin/bash
# Setup script for Process Documentation task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Process Documentation & Provenance task ==="

# 1. Clean previous results
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/initial_counts.json 2>/dev/null || true
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# 2. Record initial DB state (to detect NEW entities)
# We need to find the active database first
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
# Find largest directory in databases folder (likely the imported USLCI)
if [ -d "$DB_DIR" ]; then
    ACTIVE_DB=$(du -s "$DB_DIR"/*/ 2>/dev/null | sort -nr | head -1 | cut -f2)
fi

ACTOR_COUNT=0
SOURCE_COUNT=0
PROCESS_COUNT=0

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ]; then
    echo "Using database at: $ACTIVE_DB"
    ACTOR_COUNT=$(derby_count "$ACTIVE_DB" "ACTORS")
    SOURCE_COUNT=$(derby_count "$ACTIVE_DB" "SOURCES")
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES")
else
    echo "No active database found yet."
fi

# Save initial counts
cat > /tmp/initial_counts.json << EOF
{
    "actors": ${ACTOR_COUNT:-0},
    "sources": ${SOURCE_COUNT:-0},
    "processes": ${PROCESS_COUNT:-0}
}
EOF

# 3. Ensure Import files are present
mkdir -p /home/ga/LCA_Imports
if [ -f "/opt/openlca_data/uslci_database.zip" ] && [ ! -f "/home/ga/LCA_Imports/uslci_database.zip" ]; then
    cp /opt/openlca_data/uslci_database.zip /home/ga/LCA_Imports/
    chown ga:ga /home/ga/LCA_Imports/uslci_database.zip
fi

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. Maximize window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Capture setup screenshot and timestamp
take_screenshot /tmp/task_initial.png
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="