#!/bin/bash
echo "=== Exporting price_sync_merge results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Query Database State
# ============================================================

# 1. Check if Audit Table exists and get column info
AUDIT_TABLE_INFO=$(mssql_query "
    SELECT 
        CASE WHEN OBJECT_ID('Pricing.MergeAuditLog', 'U') IS NOT NULL THEN 1 ELSE 0 END as Exists,
        (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'Pricing' AND TABLE_NAME = 'MergeAuditLog') as ColCount
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
" "AdventureWorks2022")

# 2. Get Audit Log Statistics
AUDIT_STATS=$(mssql_query "
    SELECT 
        (SELECT COUNT(*) FROM Pricing.MergeAuditLog) as TotalRows,
        (SELECT COUNT(*) FROM Pricing.MergeAuditLog WHERE MergeAction = 'INSERT') as InsertRows,
        (SELECT COUNT(*) FROM Pricing.MergeAuditLog WHERE MergeAction = 'UPDATE') as UpdateRows,
        (SELECT COUNT(*) FROM Pricing.MergeAuditLog WHERE MergeAction = 'UPDATE' AND OldListPrice = NewListPrice) as SpuriousUpdates,
        (SELECT COUNT(*) FROM Pricing.MergeAuditLog WHERE PriceChangePercent IS NOT NULL) as CalcRows
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
" "AdventureWorks2022")

# 3. Check PriceMaster Final State
MASTER_STATS=$(mssql_query "
    SELECT COUNT(*) as FinalCount FROM Pricing.PriceMaster
" "AdventureWorks2022" | grep -E '^[0-9]+' | tr -d ' \r')

# 4. Check Summary View
VIEW_CHECK=$(mssql_query "
    SELECT 
        CASE WHEN OBJECT_ID('Pricing.vw_MergeSummary', 'V') IS NOT NULL THEN 1 ELSE 0 END as ViewExists,
        (SELECT COUNT(*) FROM Pricing.vw_MergeSummary) as ViewRows
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
" "AdventureWorks2022")

# 5. Check Audit Timestamp (Anti-Gaming)
# Ensure timestamps in the table are AFTER the task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Convert unix timestamp to SQL format or check relative to GETDATE() in SQL is harder without timezone sync
# Easier: Check if MIN(AuditTimestamp) is recent.
TIMESTAMP_CHECK=$(mssql_query "
    SELECT TOP 1 
        CASE WHEN DATEDIFF(minute, MIN(AuditTimestamp), GETDATE()) < 60 THEN 1 ELSE 0 END as IsRecent
    FROM Pricing.MergeAuditLog
" "AdventureWorks2022" | grep -E '^[0-1]' | head -1 | tr -d ' \r')

# Combine all into one JSON
cat > /tmp/merge_result.json << EOF
{
    "audit_table": ${AUDIT_TABLE_INFO:-"{}"},
    "audit_stats": ${AUDIT_STATS:-"{}"},
    "master_final_count": ${MASTER_STATS:-0},
    "view_check": ${VIEW_CHECK:-"{}"},
    "timestamp_valid": ${TIMESTAMP_CHECK:-0},
    "task_start_ts": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/merge_result.json"
cat /tmp/merge_result.json
echo "=== Export complete ==="