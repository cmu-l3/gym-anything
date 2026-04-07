#!/bin/bash
# Export results for index_health_maintenance task
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if SQL Server is running
MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

# Initialize variables
SCHEMA_EXISTS="false"
REPORT_TABLE_EXISTS="false"
OVERLAP_TABLE_EXISTS="false"
ANALYZE_PROC_EXISTS="false"
OVERLAP_PROC_EXISTS="false"
REPORT_ROW_COUNT=0
OVERLAP_ROW_COUNT=0
REPORT_COLUMNS_VALID="false"
RECOMMENDED_ACTION_VALID="false"
SIZE_CALC_VALID="false"
INDEX_TYPES_FOUND=0
FILE_EXISTS="false"
FILE_CONTENT_VALID="false"
FILE_SIZE=0

if [ "$MSSQL_RUNNING" = "true" ]; then
    # 1. Check Schema
    count=$(mssql_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'DBAMaintenance'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$count" -gt 0 ] && SCHEMA_EXISTS="true"

    # 2. Check Tables
    count=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('DBAMaintenance.IndexHealthReport') AND type = 'U'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$count" -gt 0 ] && REPORT_TABLE_EXISTS="true"

    count=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('DBAMaintenance.OverlappingIndexes') AND type = 'U'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$count" -gt 0 ] && OVERLAP_TABLE_EXISTS="true"

    # 3. Check Procedures
    count=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_AnalyzeIndexHealth' AND schema_id = SCHEMA_ID('DBAMaintenance')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$count" -gt 0 ] && ANALYZE_PROC_EXISTS="true"

    count=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_DetectOverlappingIndexes' AND schema_id = SCHEMA_ID('DBAMaintenance')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$count" -gt 0 ] && OVERLAP_PROC_EXISTS="true"

    # 4. Check IndexHealthReport Data
    if [ "$REPORT_TABLE_EXISTS" = "true" ]; then
        # Check columns
        cols=$(mssql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'DBAMaintenance' AND TABLE_NAME = 'IndexHealthReport'" "AdventureWorks2022" | tr -d ' \r\n')
        [ "$cols" -ge 9 ] && REPORT_COLUMNS_VALID="true"

        # Check row count
        REPORT_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM DBAMaintenance.IndexHealthReport" "AdventureWorks2022" | tr -d ' \r\n')
        
        # Check RecommendedAction validity
        invalid_actions=$(mssql_query "SELECT COUNT(*) FROM DBAMaintenance.IndexHealthReport WHERE RecommendedAction NOT IN ('REBUILD', 'REORGANIZE', 'NONE')" "AdventureWorks2022" | tr -d ' \r\n')
        [ "$invalid_actions" -eq 0 ] && RECOMMENDED_ACTION_VALID="true"

        # Check SizeKB calculation (approximate check: SizeKB should be close to PageCount * 8)
        # We allow small deviance, but generally it's exactly 8KB per page
        bad_calc=$(mssql_query "SELECT COUNT(*) FROM DBAMaintenance.IndexHealthReport WHERE ABS(SizeKB - (PageCount * 8)) > 8" "AdventureWorks2022" | tr -d ' \r\n')
        [ "$bad_calc" -eq 0 ] && SIZE_CALC_VALID="true"

        # Check IndexType diversity
        INDEX_TYPES_FOUND=$(mssql_query "SELECT COUNT(DISTINCT IndexType) FROM DBAMaintenance.IndexHealthReport" "AdventureWorks2022" | tr -d ' \r\n')
    fi

    # 5. Check OverlappingIndexes Data
    if [ "$OVERLAP_TABLE_EXISTS" = "true" ]; then
        OVERLAP_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM DBAMaintenance.OverlappingIndexes" "AdventureWorks2022" | tr -d ' \r\n')
    fi
fi

# 6. Check Output File
FILE_PATH="/home/ga/Documents/exports/index_maintenance.sql"
if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    
    # Check for ALTER INDEX statements OR a comment if empty
    if grep -iq "ALTER INDEX" "$FILE_PATH" || grep -q "\-\-" "$FILE_PATH"; then
        FILE_CONTENT_VALID="true"
    fi
fi

# Create JSON Result
cat > /tmp/index_health_result.json <<EOF
{
    "schema_exists": $SCHEMA_EXISTS,
    "report_table_exists": $REPORT_TABLE_EXISTS,
    "overlap_table_exists": $OVERLAP_TABLE_EXISTS,
    "analyze_proc_exists": $ANALYZE_PROC_EXISTS,
    "overlap_proc_exists": $OVERLAP_PROC_EXISTS,
    "report_row_count": ${REPORT_ROW_COUNT:-0},
    "overlap_row_count": ${OVERLAP_ROW_COUNT:-0},
    "report_columns_valid": $REPORT_COLUMNS_VALID,
    "recommended_action_valid": $RECOMMENDED_ACTION_VALID,
    "size_calc_valid": $SIZE_CALC_VALID,
    "index_types_found": ${INDEX_TYPES_FOUND:-0},
    "file_exists": $FILE_EXISTS,
    "file_content_valid": $FILE_CONTENT_VALID,
    "file_size": $FILE_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to avoid permissions issues if agent owns file
cp /tmp/index_health_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json