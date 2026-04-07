#!/bin/bash
# Export script for Custom LCIA Method task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Custom LCIA Method Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check output file
OUTPUT_FILE="/home/ga/LCA_Results/single_score_results.csv"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Query Derby Database for Method Verification
# We need to find the active database first
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    CURRENT_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${CURRENT_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${CURRENT_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

METHOD_FOUND="false"
CATEGORIES_JSON="[]"
FACTORS_JSON="[]"
NW_SETS_JSON="[]"
NW_FACTORS_JSON="[]"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database at $ACTIVE_DB..."
    
    # Close OpenLCA to unlock Derby
    close_openlca
    sleep 3

    # Query 1: Find the Method ID
    METHOD_NAME="Corporate Eco-Strategy 2025"
    METHOD_ID_QUERY="SELECT ID FROM TBL_IMPACT_METHODS WHERE NAME = '${METHOD_NAME}' FETCH FIRST 1 ROWS ONLY;"
    METHOD_ID_RAW=$(derby_query "$ACTIVE_DB" "$METHOD_ID_QUERY")
    # Extract ID (remove headers/whitespace)
    METHOD_ID=$(echo "$METHOD_ID_RAW" | grep -oP '^\s*\K\d+' | head -1)

    if [ -n "$METHOD_ID" ]; then
        METHOD_FOUND="true"
        echo "Method found with ID: $METHOD_ID"

        # Query 2: Get Categories for this Method
        # TBL_IMPACT_CATEGORIES typically links to Method via F_IMPACT_METHOD column
        CATS_QUERY="SELECT NAME, REFERENCE_UNIT FROM TBL_IMPACT_CATEGORIES WHERE F_IMPACT_METHOD = ${METHOD_ID};"
        CATS_RAW=$(derby_query "$ACTIVE_DB" "$CATS_QUERY")
        # Format crude JSON from query output (simulated parsing)
        # We will capture the raw output and let python parse it, or basic grep
        CATEGORIES_RAW="$CATS_RAW"

        # Query 3: Check Factors (Characterization)
        # Factors link to Category. We need Category IDs first.
        # This is getting complex for shell. We will dump raw query outputs.
        
        # Dump TBL_IMPACT_FACTORS for the categories of this method
        # Join is hard in ij interactive, so we select based on likely IDs or just dump relevant tables
        
        # Helper: Dump tables to temp files for Python to parse
        derby_query "$ACTIVE_DB" "SELECT * FROM TBL_IMPACT_CATEGORIES WHERE F_IMPACT_METHOD = ${METHOD_ID};" > /tmp/db_categories.txt
        
        # Get Category IDs to query factors
        CAT_IDS=$(grep -oP '^\s*\K\d+' /tmp/db_categories.txt | tr '\n' ',' | sed 's/,$//')
        
        if [ -n "$CAT_IDS" ]; then
            # Get Impact Factors (F_IMPACT_CATEGORY in list)
            # Need to join with TBL_FLOWS to get flow names, but TBL_FLOWS is huge.
            # We will fetch factors and their flow IDs, then fetch those flow names.
            derby_query "$ACTIVE_DB" "SELECT F_FLOW, VALUE, F_IMPACT_CATEGORY FROM TBL_IMPACT_FACTORS WHERE F_IMPACT_CATEGORY IN ($CAT_IDS);" > /tmp/db_factors.txt
            
            # Get Flow IDs from factors
            FLOW_IDS=$(awk '{print $1}' /tmp/db_factors.txt | grep -E '^[0-9]+$' | sort -u | tr '\n' ',' | sed 's/,$//')
            if [ -n "$FLOW_IDS" ]; then
                derby_query "$ACTIVE_DB" "SELECT ID, NAME FROM TBL_FLOWS WHERE ID IN ($FLOW_IDS);" > /tmp/db_flows.txt
            fi
        fi

        # Query 4: NW Sets (Normalization and Weighting)
        # TBL_NW_SETS links to Method via F_IMPACT_METHOD
        derby_query "$ACTIVE_DB" "SELECT ID, NAME, WEIGHTED_SCORE_UNIT FROM TBL_NW_SETS WHERE F_IMPACT_METHOD = ${METHOD_ID};" > /tmp/db_nw_sets.txt
        
        # Get NW Set IDs
        SET_IDS=$(grep -oP '^\s*\K\d+' /tmp/db_nw_sets.txt | tr '\n' ',' | sed 's/,$//')
        
        if [ -n "$SET_IDS" ]; then
            # Query 5: NW Factors
            # TBL_NW_FACTORS links to NW Set via F_NW_SET
            derby_query "$ACTIVE_DB" "SELECT F_NW_SET, F_IMPACT_CATEGORY, NORMALISATION_FACTOR, WEIGHTING_FACTOR FROM TBL_NW_FACTORS WHERE F_NW_SET IN ($SET_IDS);" > /tmp/db_nw_factors.txt
        fi
    fi
else
    echo "No active database found to query."
fi

# 4. Create Result JSON
# We will embed the raw text content of the DB dumps into the JSON
# Python verifier will parse the text.

escape_json_string() {
    # Simple escape for file content to be valid JSON string
    cat "$1" 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

CATS_CONTENT=$(escape_json_string /tmp/db_categories.txt)
FACTORS_CONTENT=$(escape_json_string /tmp/db_factors.txt)
FLOWS_CONTENT=$(escape_json_string /tmp/db_flows.txt)
NW_SETS_CONTENT=$(escape_json_string /tmp/db_nw_sets.txt)
NW_FACTORS_CONTENT=$(escape_json_string /tmp/db_nw_factors.txt)

cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "method_found": $METHOD_FOUND,
    "db_dump_categories": $CATS_CONTENT,
    "db_dump_factors": $FACTORS_CONTENT,
    "db_dump_flows": $FLOWS_CONTENT,
    "db_dump_nw_sets": $NW_SETS_CONTENT,
    "db_dump_nw_factors": $NW_FACTORS_CONTENT
}
EOF

# Clean up temp files
rm -f /tmp/db_*.txt

echo "Result saved to /tmp/task_result.json"