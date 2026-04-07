#!/bin/bash
# Export script for Corporate Flow Taxonomy task
# Verifies database content via Derby queries and file system checks

source /workspace/scripts/task_utils.sh

echo "=== Exporting Corporate Flow Taxonomy Result ==="

# 1. Capture final visual state
take_screenshot /tmp/task_end_screenshot.png

# 2. Gather timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
DB_PATH="/home/ga/openLCA-data-1.4/databases/ChemCorp_LCA"

# 3. Check Database Existence and Timestamp
DB_EXISTS="false"
DB_CREATED_DURING_TASK="false"
DB_SIZE_MB=0

if [ -d "$DB_PATH" ] && [ -f "$DB_PATH/service.properties" ]; then
    DB_EXISTS="true"
    DB_SIZE_MB=$(du -sm "$DB_PATH" | cut -f1)
    
    # Check creation time of service.properties
    DB_CTIME=$(stat -c %Y "$DB_PATH/service.properties" 2>/dev/null || echo "0")
    if [ "$DB_CTIME" -gt "$TASK_START" ]; then
        DB_CREATED_DURING_TASK="true"
    fi
fi

# 4. Close OpenLCA to release Derby database locks for querying
echo "Closing OpenLCA for verification..."
close_openlca
sleep 5

# 5. Query Derby Database Content
# Initialize counters
FLOW_COUNT=0
ELEM_FLOW_COUNT=0
PROD_FLOW_COUNT=0
CATEGORY_COUNT=0
FLOW_PROP_LINK_COUNT=0

if [ "$DB_EXISTS" = "true" ]; then
    echo "Querying Derby database at $DB_PATH..."
    
    # Get total flow count
    FLOW_COUNT=$(derby_query "$DB_PATH" "SELECT COUNT(*) FROM TBL_FLOWS;" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # Get elementary flow count
    ELEM_FLOW_COUNT=$(derby_query "$DB_PATH" "SELECT COUNT(*) FROM TBL_FLOWS WHERE FLOW_TYPE = 'ELEMENTARY_FLOW';" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # Get product flow count
    PROD_FLOW_COUNT=$(derby_query "$DB_PATH" "SELECT COUNT(*) FROM TBL_FLOWS WHERE FLOW_TYPE = 'PRODUCT_FLOW';" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # Get category count
    CATEGORY_COUNT=$(derby_query "$DB_PATH" "SELECT COUNT(*) FROM TBL_CATEGORIES;" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # Get flow property factor count (links between flows and properties)
    FLOW_PROP_LINK_COUNT=$(derby_query "$DB_PATH" "SELECT COUNT(*) FROM TBL_FLOW_PROPERTY_FACTORS;" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    # Export all flow names and category names to text files for Python parsing
    # Note: Derby formatting is messy, we'll grep this file later or read it in python
    derby_query "$DB_PATH" "SELECT NAME FROM TBL_FLOWS;" > /tmp/db_flow_names.txt
    derby_query "$DB_PATH" "SELECT NAME FROM TBL_CATEGORIES;" > /tmp/db_category_names.txt
fi

# 6. Sanitize Counts
FLOW_COUNT=${FLOW_COUNT:-0}
ELEM_FLOW_COUNT=${ELEM_FLOW_COUNT:-0}
PROD_FLOW_COUNT=${PROD_FLOW_COUNT:-0}
CATEGORY_COUNT=${CATEGORY_COUNT:-0}
FLOW_PROP_LINK_COUNT=${FLOW_PROP_LINK_COUNT:-0}

# 7. Check specific flow names (using grep on the dump)
HAS_CATALYST_RESIDUE=$(grep -ci "Catalyst residue X-47" /tmp/db_flow_names.txt || echo "0")
HAS_VOC=$(grep -ci "Volatile organic compound mix A" /tmp/db_flow_names.txt || echo "0")
HAS_SULFONATE=$(grep -ci "Sulfonate byproduct" /tmp/db_flow_names.txt || echo "0")
HAS_HEAVY_METAL=$(grep -ci "Heavy metal sludge" /tmp/db_flow_names.txt || echo "0")
HAS_THERMAL=$(grep -ci "Thermal effluent" /tmp/db_flow_names.txt || echo "0")
HAS_PALLADIUM=$(grep -ci "Palladium catalyst intermediate" /tmp/db_flow_names.txt || echo "0")
HAS_TOLUENE=$(grep -ci "Reclaimed toluene solvent" /tmp/db_flow_names.txt || echo "0")
HAS_ETHYL=$(grep -ci "Ethyl acetate solvent grade B" /tmp/db_flow_names.txt || echo "0")

# 8. Check specific category keywords
HAS_CAT_MFG=$(grep -ci "Manufacturing" /tmp/db_category_names.txt || echo "0")
HAS_CAT_EFF=$(grep -ci "Process effluent" /tmp/db_category_names.txt || echo "0")
HAS_CAT_CAT=$(grep -ci "Catalysts" /tmp/db_category_names.txt || echo "0")
HAS_CAT_SOL=$(grep -ci "Solvents" /tmp/db_category_names.txt || echo "0")

# 9. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_exists": $DB_EXISTS,
    "db_created_during_task": $DB_CREATED_DURING_TASK,
    "db_size_mb": $DB_SIZE_MB,
    "flow_count": $FLOW_COUNT,
    "elem_flow_count": $ELEM_FLOW_COUNT,
    "prod_flow_count": $PROD_FLOW_COUNT,
    "category_count": $CATEGORY_COUNT,
    "flow_prop_link_count": $FLOW_PROP_LINK_COUNT,
    "flow_checks": {
        "catalyst_residue": $([ "$HAS_CATALYST_RESIDUE" -gt 0 ] && echo "true" || echo "false"),
        "voc_mix": $([ "$HAS_VOC" -gt 0 ] && echo "true" || echo "false"),
        "sulfonate": $([ "$HAS_SULFONATE" -gt 0 ] && echo "true" || echo "false"),
        "heavy_metal": $([ "$HAS_HEAVY_METAL" -gt 0 ] && echo "true" || echo "false"),
        "thermal_effluent": $([ "$HAS_THERMAL" -gt 0 ] && echo "true" || echo "false"),
        "palladium": $([ "$HAS_PALLADIUM" -gt 0 ] && echo "true" || echo "false"),
        "toluene": $([ "$HAS_TOLUENE" -gt 0 ] && echo "true" || echo "false"),
        "ethyl_acetate": $([ "$HAS_ETHYL" -gt 0 ] && echo "true" || echo "false")
    },
    "category_checks": {
        "manufacturing": $([ "$HAS_CAT_MFG" -gt 0 ] && echo "true" || echo "false"),
        "effluent": $([ "$HAS_CAT_EFF" -gt 0 ] && echo "true" || echo "false"),
        "catalysts": $([ "$HAS_CAT_CAT" -gt 0 ] && echo "true" || echo "false"),
        "solvents": $([ "$HAS_CAT_SOL" -gt 0 ] && echo "true" || echo "false")
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# 10. Save and clean up
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="