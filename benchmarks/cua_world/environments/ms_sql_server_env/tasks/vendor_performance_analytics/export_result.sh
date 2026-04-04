#!/bin/bash
# Export results for vendor_performance_analytics task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

# Check SQL Server running
MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

ADS_RUNNING="false"
if ads_is_running; then ADS_RUNNING="true"; fi

# ── Check: Analytics schema exists ───────────────────────────────────────────
ANALYTICS_SCHEMA_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    SC=$(mssql_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'Analytics'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$SC" -gt 0 ] 2>/dev/null && ANALYTICS_SCHEMA_EXISTS="true"
fi

# ── Check: VendorPerformance table exists ─────────────────────────────────────
VP_TABLE_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    TC=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('Analytics.VendorPerformance') AND type = 'U'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$TC" -gt 0 ] 2>/dev/null && VP_TABLE_EXISTS="true"
fi

# ── Check: Stored procedure exists ───────────────────────────────────────────
PROC_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    PC=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_VendorPerformanceReport'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$PC" -gt 0 ] 2>/dev/null && PROC_EXISTS="true"
fi

# ── Check columns of VendorPerformance ────────────────────────────────────────
COLUMNS_FOUND=""
HAS_REQUIRED_COLUMNS="false"
COLUMN_COUNT=0

if [ "$VP_TABLE_EXISTS" = "true" ]; then
    COLUMNS_FOUND=$(mssql_query "
        SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'Analytics' AND TABLE_NAME = 'VendorPerformance'
        ORDER BY ORDINAL_POSITION
    " "AdventureWorks2022" | tr -d '\r' | grep -v '^$' | tr '\n' ',')

    COLUMN_COUNT=$(mssql_query "
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'Analytics' AND TABLE_NAME = 'VendorPerformance'
    " "AdventureWorks2022" | tr -d ' \r\n')

    # Check for all 7 required columns
    REQUIRED_COLS=("VendorID" "VendorName" "TotalOrders" "TotalLineItems" "AvgUnitCostVariance" "OnTimeDeliveryRate" "VendorRank")
    FOUND_COLS=0
    cols_lower=$(echo "$COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
    for col in "${REQUIRED_COLS[@]}"; do
        col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
        if echo "$cols_lower" | grep -qiE "(^|,)${col_lower}(,|$)"; then
            FOUND_COLS=$((FOUND_COLS + 1))
        fi
    done
    [ "$FOUND_COLS" -ge 7 ] && HAS_REQUIRED_COLUMNS="true"
fi

# ── Row count and data validation ─────────────────────────────────────────────
VP_ROW_COUNT=0
HAS_DATA="false"

VENDOR_RANK_VALID="false"
DELIVERY_RATE_VALID="false"
VENDOR_NAME_MATCH_COUNT=0

if [ "$VP_TABLE_EXISTS" = "true" ]; then
    VP_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Analytics.VendorPerformance" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
    VP_ROW_COUNT=${VP_ROW_COUNT:-0}

    if [ "$VP_ROW_COUNT" -gt 0 ] 2>/dev/null; then
        HAS_DATA="true"

        # Check VendorRank: min should be 1, max should equal distinct rank values (DENSE_RANK means no gaps)
        RANK_MIN=$(mssql_query "SELECT MIN(VendorRank) FROM Analytics.VendorPerformance" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        RANK_MAX=$(mssql_query "SELECT MAX(VendorRank) FROM Analytics.VendorPerformance" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        DISTINCT_RANKS=$(mssql_query "SELECT COUNT(DISTINCT VendorRank) FROM Analytics.VendorPerformance" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)

        # DENSE_RANK: max rank = number of distinct rank values (sequential, no gaps)
        # VendorRank min=1 and the ranks are sequential integers
        if [ "${RANK_MIN:-99}" = "1" ] && [ "${RANK_MAX:-0}" = "${DISTINCT_RANKS:-0}" ] 2>/dev/null; then
            VENDOR_RANK_VALID="true"
        fi

        # Check OnTimeDeliveryRate is between 0 and 1
        RATE_MIN=$(mssql_query "SELECT CAST(MIN(OnTimeDeliveryRate) AS DECIMAL(10,4)) FROM Analytics.VendorPerformance" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        RATE_MAX=$(mssql_query "SELECT CAST(MAX(OnTimeDeliveryRate) AS DECIMAL(10,4)) FROM Analytics.VendorPerformance" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        # Check using Python for decimal comparison
        RATE_VALID=$(python3 -c "
try:
    rmin = float('${RATE_MIN:-99}')
    rmax = float('${RATE_MAX:-99}')
    print('true' if 0.0 <= rmin and rmax <= 1.0 else 'false')
except:
    print('false')
" 2>/dev/null)
        DELIVERY_RATE_VALID="${RATE_VALID:-false}"

        # Cross-validate: top 3 VendorNames from VendorPerformance should exist in Purchasing.Vendor
        TOP_VENDORS=$(mssql_query "
            SELECT TOP 3 VendorName FROM Analytics.VendorPerformance
            ORDER BY VendorRank ASC
        " "AdventureWorks2022" 2>/dev/null | tr -d '\r' | grep -v '^$')

        if [ -n "$TOP_VENDORS" ]; then
            while IFS= read -r vname; do
                vname_clean=$(echo "$vname" | sed "s/'/''/g")
                EXISTS=$(mssql_query "SELECT COUNT(*) FROM Purchasing.Vendor WHERE Name = '${vname_clean}'" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
                if [ "${EXISTS:-0}" -gt 0 ] 2>/dev/null; then
                    VENDOR_NAME_MATCH_COUNT=$((VENDOR_NAME_MATCH_COUNT + 1))
                fi
            done <<< "$TOP_VENDORS"
        fi
    fi
fi

# Build JSON result
cat > /tmp/vendor_perf_result.json << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "analytics_schema_exists": $ANALYTICS_SCHEMA_EXISTS,
    "vp_table_exists": $VP_TABLE_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "has_required_columns": $HAS_REQUIRED_COLUMNS,
    "column_count": $COLUMN_COUNT,
    "columns_found": "$COLUMNS_FOUND",
    "vp_row_count": ${VP_ROW_COUNT:-0},
    "has_data": $HAS_DATA,
    "vendor_rank_valid": $VENDOR_RANK_VALID,
    "delivery_rate_valid": $DELIVERY_RATE_VALID,
    "vendor_name_match_count": $VENDOR_NAME_MATCH_COUNT,
    "rate_min": "${RATE_MIN:-null}",
    "rate_max": "${RATE_MAX:-null}",
    "rank_min": "${RANK_MIN:-null}",
    "rank_max": "${RANK_MAX:-null}",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/vendor_perf_result.json 2>/dev/null || true
echo "Result saved to /tmp/vendor_perf_result.json"
cat /tmp/vendor_perf_result.json
echo ""
echo "=== Export complete ==="
exit 0
