#!/bin/bash
# Export results for hr_workforce_analytics task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

ADS_RUNNING="false"
if ads_is_running; then ADS_RUNNING="true"; fi

# ── Check: HumanResources.WorkforceSummary table ──────────────────────────────
TABLE_EXISTS="false"
TABLE_ROW_COUNT=0
COLUMNS_FOUND=""
HAS_REQUIRED_COLUMNS="false"
REQUIRED_COLUMN_COUNT=0
INDEX_EXISTS="false"

if [ "$MSSQL_RUNNING" = "true" ]; then
    TC=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('HumanResources.WorkforceSummary') AND type = 'U'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${TC:-0}" -gt 0 ] 2>/dev/null && TABLE_EXISTS="true"

    if [ "$TABLE_EXISTS" = "true" ]; then
        COLUMNS_FOUND=$(mssql_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'HumanResources' AND TABLE_NAME = 'WorkforceSummary'
            ORDER BY ORDINAL_POSITION
        " "AdventureWorks2022" | tr -d '\r' | grep -v '^$' | tr '\n' ',')

        REQUIRED_COLS=("DepartmentID" "DepartmentName" "ActiveEmployeeCount" "AvgHourlyRate" "FemaleCount" "MaleCount" "AvgTenureDays" "SeniorEmployeeCount")
        REQUIRED_COLUMN_COUNT=0
        cols_lower=$(echo "$COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
        for col in "${REQUIRED_COLS[@]}"; do
            col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
            if echo "$cols_lower" | grep -qiE "(^|,)${col_lower}(,|$)"; then
                REQUIRED_COLUMN_COUNT=$((REQUIRED_COLUMN_COUNT + 1))
            fi
        done
        [ "$REQUIRED_COLUMN_COUNT" -ge 7 ] && HAS_REQUIRED_COLUMNS="true"

        TABLE_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM HumanResources.WorkforceSummary" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        TABLE_ROW_COUNT=${TABLE_ROW_COUNT:-0}

        # Check for non-clustered index on DepartmentID
        IC=$(mssql_query "
            SELECT COUNT(*) FROM sys.indexes i
            JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
            JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE i.object_id = OBJECT_ID('HumanResources.WorkforceSummary')
            AND i.type = 2
            AND c.name = 'DepartmentID'
        " "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        [ "${IC:-0}" -gt 0 ] 2>/dev/null && INDEX_EXISTS="true"
    fi
fi

# ── Check: Stored procedure exists ───────────────────────────────────────────
PROC_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    PC=$(mssql_query "
        SELECT COUNT(*) FROM sys.procedures p
        JOIN sys.schemas s ON p.schema_id = s.schema_id
        WHERE p.name = 'usp_RefreshWorkforceSummary' AND s.name = 'HumanResources'
    " "AdventureWorks2022" | tr -d ' \r\n')
    [ "${PC:-0}" -gt 0 ] 2>/dev/null && PROC_EXISTS="true"
fi

# ── Data quality checks ───────────────────────────────────────────────────────
GENDER_COUNTS_VALID="false"
HOURLY_RATE_VALID="false"
DEPT_NAME_MATCH_COUNT=0

if [ "$TABLE_EXISTS" = "true" ] && [ "${TABLE_ROW_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    # Check FemaleCount + MaleCount approximates ActiveEmployeeCount
    cols_lower=$(echo "$COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
    if echo "$cols_lower" | grep -q "femalecount" && echo "$cols_lower" | grep -q "malecount"; then
        GENDER_SUM_MATCHES=$(mssql_query "
            SELECT COUNT(*) FROM HumanResources.WorkforceSummary
            WHERE (FemaleCount + MaleCount) = ActiveEmployeeCount
        " "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        [ "${GENDER_SUM_MATCHES:-0}" -gt 0 ] 2>/dev/null && GENDER_COUNTS_VALID="true"
    fi

    # Check AvgHourlyRate > 0 for all rows
    if echo "$cols_lower" | grep -q "avghourlyrate"; then
        RATE_VALID=$(mssql_query "
            SELECT COUNT(*) FROM HumanResources.WorkforceSummary WHERE AvgHourlyRate > 0
        " "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        [ "${RATE_VALID:-0}" -gt 0 ] 2>/dev/null && HOURLY_RATE_VALID="true"
    fi

    # Cross-validate: top 3 DepartmentNames should exist in HumanResources.Department
    TOP_DEPTS=$(mssql_query "
        SELECT TOP 3 DepartmentName FROM HumanResources.WorkforceSummary
        ORDER BY ActiveEmployeeCount DESC
    " "AdventureWorks2022" 2>/dev/null | tr -d '\r' | grep -v '^$')

    if [ -n "$TOP_DEPTS" ]; then
        while IFS= read -r dname; do
            dname_clean=$(echo "$dname" | sed "s/'/''/g")
            EXISTS=$(mssql_query "SELECT COUNT(*) FROM HumanResources.Department WHERE Name = '${dname_clean}'" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
            if [ "${EXISTS:-0}" -gt 0 ] 2>/dev/null; then
                DEPT_NAME_MATCH_COUNT=$((DEPT_NAME_MATCH_COUNT + 1))
            fi
        done <<< "$TOP_DEPTS"
    fi
fi

# Build JSON result
cat > /tmp/hr_workforce_result.json << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "table_exists": $TABLE_EXISTS,
    "table_row_count": ${TABLE_ROW_COUNT:-0},
    "has_required_columns": $HAS_REQUIRED_COLUMNS,
    "required_column_count": $REQUIRED_COLUMN_COUNT,
    "columns_found": "$COLUMNS_FOUND",
    "index_exists": $INDEX_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "gender_counts_valid": $GENDER_COUNTS_VALID,
    "hourly_rate_valid": $HOURLY_RATE_VALID,
    "dept_name_match_count": $DEPT_NAME_MATCH_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/hr_workforce_result.json 2>/dev/null || true
echo "Result saved to /tmp/hr_workforce_result.json"
cat /tmp/hr_workforce_result.json
echo ""
echo "=== Export complete ==="
exit 0
