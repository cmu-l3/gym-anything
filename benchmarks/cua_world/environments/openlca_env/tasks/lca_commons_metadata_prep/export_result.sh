#!/bin/bash
# export_result.sh for lca_commons_metadata_prep

source /workspace/scripts/task_utils.sh

echo "=== Exporting LCA Metadata Verification Data ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Identify the active database
# We look for the most recently modified database directory
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
LATEST_TIME=0

for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    MOD_TIME=$(stat -c %Y "$db_path" 2>/dev/null || echo "0")
    if [ "$MOD_TIME" -gt "$LATEST_TIME" ]; then
        LATEST_TIME="$MOD_TIME"
        ACTIVE_DB="$db_path"
    fi
done

echo "Active database detected: $ACTIVE_DB"

# 3. Initialize verification variables
ACTOR_FOUND="false"
SOURCE_FOUND="false"
PROCESS_FOUND="false"
ACTOR_LINKED="false"
SOURCE_LINKED="false"
TECH_DESC_MATCH="false"
VALIDITY_MATCH="false"
ACTOR_ID=""
SOURCE_ID=""
PROCESS_ID=""
DATA_GENERATOR_ID=""

# 4. Query Derby Database if active DB found
if [ -n "$ACTIVE_DB" ]; then
    
    # Check Actor
    # TBL_ACTORS: ID, NAME
    ACTOR_QUERY=$(derby_query "$ACTIVE_DB" "SELECT ID, NAME FROM TBL_ACTORS WHERE LOWER(NAME) LIKE '%ecotech%consulting%'")
    if echo "$ACTOR_QUERY" | grep -qi "EcoTech"; then
        ACTOR_FOUND="true"
        # Extract ID (simple parsing assuming ID is first column)
        ACTOR_ID=$(echo "$ACTOR_QUERY" | grep -i "EcoTech" | awk '{print $1}')
    fi

    # Check Source
    # TBL_SOURCES: ID, NAME
    SOURCE_QUERY=$(derby_query "$ACTIVE_DB" "SELECT ID, NAME FROM TBL_SOURCES WHERE LOWER(NAME) LIKE '%q4%2024%production%report%'")
    if echo "$SOURCE_QUERY" | grep -qi "Q4 2024"; then
        SOURCE_FOUND="true"
        SOURCE_ID=$(echo "$SOURCE_QUERY" | grep -i "Q4 2024" | awk '{print $1}')
    fi

    # Check Process and Linkages
    # TBL_PROCESSES: ID, NAME, F_DATA_GENERATOR
    # Note: F_DATA_GENERATOR links to TBL_ACTORS.ID
    PROCESS_QUERY=$(derby_query "$ACTIVE_DB" "SELECT ID, NAME, F_DATA_GENERATOR FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%bio-based%polyol%'")
    
    if echo "$PROCESS_QUERY" | grep -qi "Bio-based Polyol"; then
        PROCESS_FOUND="true"
        # Extract Process ID and Data Generator ID
        # Output format typically: ID | NAME | F_DATA_GENERATOR
        PROCESS_ROW=$(echo "$PROCESS_QUERY" | grep -i "Bio-based Polyol")
        PROCESS_ID=$(echo "$PROCESS_ROW" | awk '{print $1}')
        DATA_GENERATOR_ID=$(echo "$PROCESS_ROW" | awk '{print $NF}') # Assuming last column if simple layout, but safest to grep
        
        # Verify Actor Link
        if [ -n "$ACTOR_ID" ] && echo "$PROCESS_ROW" | grep -q "$ACTOR_ID"; then
            ACTOR_LINKED="true"
        fi

        # Verify Source Link
        # Source links are often in a mapping table TBL_PROCESS_SOURCES (F_OWNER -> Process, F_SOURCE -> Source)
        # OR sometimes in TBL_PROCESS_DOC if it's the "Publication" field.
        # Let's check TBL_PROCESS_DOC first as that's where "Publication" usually lives in 1.4 schema which 2.x supports.
        # Actually in 2.x, it might be F_PUBLICATION in TBL_PROCESS_DOC.
        
        DOC_QUERY=$(derby_query "$ACTIVE_DB" "SELECT TECHNOLOGY_DESCRIPTION, VALID_FROM, F_PUBLICATION FROM TBL_PROCESS_DOC WHERE ID = $PROCESS_ID")
        
        # If ID mapping isn't 1:1 on ID column, we might need to join, but usually Process.ID = ProcessDoc.ID in openLCA Derby.
        # Let's try finding the doc by ID.
        if echo "$DOC_QUERY" | grep -qi "Enzymatic hydrolysis"; then
            TECH_DESC_MATCH="true"
        fi
        
        if echo "$DOC_QUERY" | grep -q "2024"; then
            VALIDITY_MATCH="true"
        fi
        
        if [ -n "$SOURCE_ID" ] && echo "$DOC_QUERY" | grep -q "$SOURCE_ID"; then
            SOURCE_LINKED="true"
        fi
        
        # Fallback check for source link in join table if not found in doc
        if [ "$SOURCE_LINKED" = "false" ] && [ -n "$SOURCE_ID" ]; then
             # Try checking generic mapping tables if F_PUBLICATION was null
             # This is a best-effort check
             true
        fi
    fi
fi

# 5. Check if OpenLCA is still running
APP_RUNNING="false"
if pgrep -f "openLCA\|openlca" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "actor_found": $ACTOR_FOUND,
    "source_found": $SOURCE_FOUND,
    "process_found": $PROCESS_FOUND,
    "actor_linked": $ACTOR_LINKED,
    "source_linked": $SOURCE_LINKED,
    "tech_desc_match": $TECH_DESC_MATCH,
    "validity_match": $VALIDITY_MATCH,
    "app_running": $APP_RUNNING,
    "active_db": "$ACTIVE_DB",
    "screenshot_path": "/tmp/task_end_screenshot.png",
    "timestamp": "$(date +%s)"
}
EOF

# 7. Move result to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export completed. Result:"
cat /tmp/task_result.json