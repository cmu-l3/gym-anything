#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Corporate ESG Taxonomy Task ==="

# 1. Clean up previous artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/initial_db_state.json 2>/dev/null || true
rm -f /home/ga/LCA_Results/esg_taxonomy_report.txt 2>/dev/null || true
mkdir -p "/home/ga/LCA_Results"
chown ga:ga "/home/ga/LCA_Results"

# 2. Ensure an empty database exists if none are present
# We want the agent to have a playground, so we'll create a blank DB if needed
DB_DIR="/home/ga/openLCA-data-1.4/databases"
mkdir -p "$DB_DIR"
chown ga:ga "$DB_DIR"

EXISTING_DBS=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l)
if [ "$EXISTING_DBS" -eq 0 ]; then
    echo "Creating empty workspace database..."
    # Copy the USLCI empty template if available, or create a directory structure
    # Since we can't easily create a valid Derby DB from bash without Java/OpenLCA running,
    # we will rely on OpenLCA to be running and the agent to create one if missing,
    # OR we copy a known empty DB template if we had one.
    # BEST APPROACH: Launch OpenLCA. If no DB, the agent will see empty Nav.
    # The task instructions imply an "active database".
    # Let's try to grab the USLCI one if available to ensure a valid state.
    USLCI_DB=$(ensure_uslci_database)
    if [ -z "$USLCI_DB" ]; then
        echo "No existing DB found. Agent may need to create one."
    fi
fi

# 3. Record Initial State (Max IDs)
# We need to find the active database to query it.
ACTIVE_DB=""
# Pick the largest DB as the likely active one
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -ge "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

INITIAL_MAX_CAT_ID=0
INITIAL_MAX_PROC_ID=0

if [ -n "$ACTIVE_DB" ]; then
    echo "Recording initial state from DB: $(basename "$ACTIVE_DB")"
    
    # Get Max ID from TBL_CATEGORIES
    RES=$(derby_query "$ACTIVE_DB" "SELECT MAX(ID) FROM TBL_CATEGORIES;")
    VAL=$(echo "$RES" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    INITIAL_MAX_CAT_ID=${VAL:-0}
    
    # Get Max ID from TBL_PROCESSES
    RES=$(derby_query "$ACTIVE_DB" "SELECT MAX(ID) FROM TBL_PROCESSES;")
    VAL=$(echo "$RES" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    INITIAL_MAX_PROC_ID=${VAL:-0}
fi

# Save to JSON for verifier
cat > /tmp/initial_db_state.json << EOF
{
    "active_db_path": "$ACTIVE_DB",
    "initial_max_cat_id": $INITIAL_MAX_CAT_ID,
    "initial_max_proc_id": $INITIAL_MAX_PROC_ID,
    "timestamp": $(date +%s)
}
EOF

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 180

# 5. UI Setup
sleep 5
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="