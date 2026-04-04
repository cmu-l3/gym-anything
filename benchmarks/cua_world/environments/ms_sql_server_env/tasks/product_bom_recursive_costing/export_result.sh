#!/bin/bash
# Export results for product_bom_recursive_costing task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

ADS_RUNNING="false"
if ads_is_running; then ADS_RUNNING="true"; fi

# ── Check: View exists ────────────────────────────────────────────────────────
VIEW_EXISTS="false"
VIEW_ROW_COUNT=0
COLUMNS_FOUND=""
HAS_REQUIRED_COLUMNS="false"
REQUIRED_COLUMN_COUNT=0
HAS_RECURSION="false"

if [ "$MSSQL_RUNNING" = "true" ]; then
    VC=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_ProductBOMHierarchy' AND schema_id = SCHEMA_ID('dbo')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${VC:-0}" -gt 0 ] 2>/dev/null && VIEW_EXISTS="true"

    if [ "$VIEW_EXISTS" = "true" ]; then
        COLUMNS_FOUND=$(mssql_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'vw_ProductBOMHierarchy' AND TABLE_SCHEMA = 'dbo'
            ORDER BY ORDINAL_POSITION
        " "AdventureWorks2022" | tr -d '\r' | grep -v '^$' | tr '\n' ',')

        REQUIRED_COLS=("AssemblyProductID" "AssemblyName" "ComponentID" "ComponentName" "BOMLevel" "PerAssemblyQty" "UnitMeasureCode")
        REQUIRED_COLUMN_COUNT=0
        cols_lower=$(echo "$COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
        for col in "${REQUIRED_COLS[@]}"; do
            col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
            if echo "$cols_lower" | grep -qiE "(^|,)${col_lower}(,|$)"; then
                REQUIRED_COLUMN_COUNT=$((REQUIRED_COLUMN_COUNT + 1))
            fi
        done
        [ "$REQUIRED_COLUMN_COUNT" -ge 6 ] && HAS_REQUIRED_COLUMNS="true"

        VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_ProductBOMHierarchy" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        VIEW_ROW_COUNT=${VIEW_ROW_COUNT:-0}

        # Check recursion: must have rows with BOMLevel > 1
        if echo "$cols_lower" | grep -q "bomlevel"; then
            DEEP_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_ProductBOMHierarchy WHERE BOMLevel > 1" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
            [ "${DEEP_COUNT:-0}" -gt 0 ] 2>/dev/null && HAS_RECURSION="true"
        fi
    fi
fi

# ── Check: Production.LifecycleCostSummary table ──────────────────────────────
TABLE_EXISTS="false"
TABLE_ROW_COUNT=0
TABLE_COLUMNS_FOUND=""
HAS_TABLE_COLUMNS="false"
TABLE_COLUMN_COUNT=0
INDEX_EXISTS="false"
HAS_COST_DATA="false"

if [ "$MSSQL_RUNNING" = "true" ]; then
    TC=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('Production.LifecycleCostSummary') AND type = 'U'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${TC:-0}" -gt 0 ] 2>/dev/null && TABLE_EXISTS="true"

    if [ "$TABLE_EXISTS" = "true" ]; then
        TABLE_COLUMNS_FOUND=$(mssql_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'Production' AND TABLE_NAME = 'LifecycleCostSummary'
            ORDER BY ORDINAL_POSITION
        " "AdventureWorks2022" | tr -d '\r' | grep -v '^$' | tr '\n' ',')

        TABLE_COLUMN_COUNT=$(mssql_query "
            SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'Production' AND TABLE_NAME = 'LifecycleCostSummary'
        " "AdventureWorks2022" | tr -d ' \r\n')

        REQUIRED_TABLE_COLS=("AssemblyProductID" "AssemblyName" "TotalBOMComponents" "MaxBOMDepth" "DirectMaterialCost" "TotalMaterialCost")
        tcols_lower=$(echo "$TABLE_COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
        FOUND_TABLE_COLS=0
        for col in "${REQUIRED_TABLE_COLS[@]}"; do
            col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
            if echo "$tcols_lower" | grep -qiE "(^|,)${col_lower}(,|$)"; then
                FOUND_TABLE_COLS=$((FOUND_TABLE_COLS + 1))
            fi
        done
        [ "$FOUND_TABLE_COLS" -ge 5 ] && HAS_TABLE_COLUMNS="true"

        TABLE_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.LifecycleCostSummary" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        TABLE_ROW_COUNT=${TABLE_ROW_COUNT:-0}

        # Check for a non-clustered index on AssemblyProductID
        IC=$(mssql_query "
            SELECT COUNT(*) FROM sys.indexes i
            JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.object_id = OBJECT_ID('Production.LifecycleCostSummary')
            AND i.type = 2
            AND c.name = 'AssemblyProductID'
        " "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        [ "${IC:-0}" -gt 0 ] 2>/dev/null && INDEX_EXISTS="true"

        # Check TotalMaterialCost > 0 for at least some rows
        if echo "$tcols_lower" | grep -q "totalmaterialcost"; then
            COST_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.LifecycleCostSummary WHERE TotalMaterialCost > 0" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
            [ "${COST_COUNT:-0}" -gt 0 ] 2>/dev/null && HAS_COST_DATA="true"
        fi
    fi
fi

# ── Check: Stored procedure exists ───────────────────────────────────────────
PROC_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    PC=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_GenerateBOMCostReport'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${PC:-0}" -gt 0 ] 2>/dev/null && PROC_EXISTS="true"
fi

# Build JSON result
cat > /tmp/bom_cost_result.json << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "view_exists": $VIEW_EXISTS,
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "has_required_columns": $HAS_REQUIRED_COLUMNS,
    "required_column_count": $REQUIRED_COLUMN_COUNT,
    "columns_found": "$COLUMNS_FOUND",
    "has_recursion": $HAS_RECURSION,
    "table_exists": $TABLE_EXISTS,
    "table_row_count": ${TABLE_ROW_COUNT:-0},
    "has_table_columns": $HAS_TABLE_COLUMNS,
    "table_column_count": ${TABLE_COLUMN_COUNT:-0},
    "table_columns_found": "$TABLE_COLUMNS_FOUND",
    "index_exists": $INDEX_EXISTS,
    "has_cost_data": $HAS_COST_DATA,
    "proc_exists": $PROC_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/bom_cost_result.json 2>/dev/null || true
echo "Result saved to /tmp/bom_cost_result.json"
cat /tmp/bom_cost_result.json
echo ""
echo "=== Export complete ==="
exit 0
