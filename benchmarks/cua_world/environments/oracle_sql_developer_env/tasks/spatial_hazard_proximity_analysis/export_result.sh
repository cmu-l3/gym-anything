#!/bin/bash
echo "=== Exporting Spatial Hazard Proximity Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Helper to sanitize integer outputs
sanitize_int() {
    local val="$1"
    local default="$2"
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "$val"
    else
        echo "$default"
    fi
}

echo "Collecting Oracle Spatial structural metrics..."

# 1. Check if SHAPE column exists and is SDO_GEOMETRY
SHAPE_COL_EXISTS="false"
SHAPE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_cols WHERE owner='EMERGENCY_MGR' AND table_name='INFRASTRUCTURE' AND column_name='SHAPE' AND data_type='SDO_GEOMETRY';" "system" | tr -d '[:space:]')
if [ "$(sanitize_int "$SHAPE_CHECK" "0")" -gt 0 ]; then
    SHAPE_COL_EXISTS="true"
fi

# 2. Check if SHAPE is populated with data
SHAPE_POPULATED_COUNT=$(oracle_query_raw "SELECT COUNT(shape) FROM emergency_mgr.infrastructure;" "system" | tr -d '[:space:]')
SHAPE_POPULATED_COUNT=$(sanitize_int "$SHAPE_POPULATED_COUNT" "0")

# 3. Check USER_SDO_GEOM_METADATA
METADATA_EXISTS="false"
METADATA_SRID="0"
META_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_sdo_geom_metadata WHERE owner='EMERGENCY_MGR' AND table_name='INFRASTRUCTURE';" "system" | tr -d '[:space:]')
if [ "$(sanitize_int "$META_CHECK" "0")" -gt 0 ]; then
    METADATA_EXISTS="true"
    METADATA_SRID=$(oracle_query_raw "SELECT srid FROM all_sdo_geom_metadata WHERE owner='EMERGENCY_MGR' AND table_name='INFRASTRUCTURE';" "system" | tr -d '[:space:]')
    METADATA_SRID=$(sanitize_int "$METADATA_SRID" "0")
fi

# 4. Check Spatial Index
INDEX_EXISTS="false"
INDEX_ITYPE="UNKNOWN"
INDEX_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_indexes WHERE owner='EMERGENCY_MGR' AND index_name='INFRA_SHAPE_IDX';" "system" | tr -d '[:space:]')
if [ "$(sanitize_int "$INDEX_CHECK" "0")" -gt 0 ]; then
    INDEX_EXISTS="true"
    INDEX_ITYPE=$(oracle_query_raw "SELECT itype_name FROM all_indexes WHERE owner='EMERGENCY_MGR' AND index_name='INFRA_SHAPE_IDX';" "system" | tr -d '[:space:]' | head -n 1)
fi

# 5. Check Analytical View
VIEW_EXISTS="false"
VIEW_ROWS=0
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='EMERGENCY_MGR' AND view_name='AT_RISK_SCHOOLS_VW';" "system" | tr -d '[:space:]')
if [ "$(sanitize_int "$VW_CHECK" "0")" -gt 0 ]; then
    VIEW_EXISTS="true"
    VW_ROWS_VAL=$(oracle_query_raw "SELECT COUNT(*) FROM emergency_mgr.at_risk_schools_vw;" "system" 2>/dev/null | tr -d '[:space:]')
    VIEW_ROWS=$(sanitize_int "$VW_ROWS_VAL" "0")
fi

# 6. Check CSV Export
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_SIZE_BYTES=0
CSV_PATH="/home/ga/Documents/exports/evacuation_schools.csv"

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE_BYTES=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# 7. Collect GUI usage evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export everything as JSON
TEMP_JSON=$(mktemp /tmp/spatial_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "shape_col_exists": $SHAPE_COL_EXISTS,
    "shape_populated_count": $SHAPE_POPULATED_COUNT,
    "metadata_exists": $METADATA_EXISTS,
    "metadata_srid": $METADATA_SRID,
    "index_exists": $INDEX_EXISTS,
    "index_itype": "$INDEX_ITYPE",
    "view_exists": $VIEW_EXISTS,
    "view_rows": $VIEW_ROWS,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE_BYTES,
    $GUI_EVIDENCE
}
EOF

# Move JSON to final location
rm -f /tmp/spatial_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/spatial_task_result.json
chmod 666 /tmp/spatial_task_result.json
rm -f "$TEMP_JSON"

echo "Results successfully exported to /tmp/spatial_task_result.json"
cat /tmp/spatial_task_result.json
echo "=== Export complete ==="