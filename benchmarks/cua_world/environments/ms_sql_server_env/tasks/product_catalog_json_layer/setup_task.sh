#!/bin/bash
# Setup for product_catalog_json_layer task
echo "=== Setting up product_catalog_json_layer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create export directory with correct permissions
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

# Remove any existing export file
rm -f /home/ga/Documents/exports/product_catalog.json

# ============================================================
# Clean up database state
# ============================================================
echo "Cleaning up database objects..."

# Drop procedures if they exist
mssql_query "IF OBJECT_ID('dbo.usp_ExportProductCatalog', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_ExportProductCatalog" "AdventureWorks2022"
mssql_query "IF OBJECT_ID('dbo.usp_ImportProductReviews', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_ImportProductReviews" "AdventureWorks2022"

# Drop staging table if exists
mssql_query "IF OBJECT_ID('Production.ProductReviewStaging', 'U') IS NOT NULL DROP TABLE Production.ProductReviewStaging" "AdventureWorks2022"

# Record initial state
echo "Recording initial state..."
INITIAL_PROCS=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name IN ('usp_ExportProductCatalog', 'usp_ImportProductReviews')" "AdventureWorks2022" | tr -d ' \r\n')
INITIAL_TABLES=$(mssql_query "SELECT COUNT(*) FROM sys.tables WHERE name = 'ProductReviewStaging'" "AdventureWorks2022" | tr -d ' \r\n')

cat > /tmp/initial_state.json << EOF
{
    "initial_procs": ${INITIAL_PROCS:-0},
    "initial_tables": ${INITIAL_TABLES:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# ============================================================
# Ensure Azure Data Studio is running
# ============================================================
echo "Ensuring Azure Data Studio is running..."

if ! ads_is_running; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    [ ! -x "$ADS_CMD" ] && ADS_CMD="azuredatastudio"
    
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio_task.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if get_ads_windows > /dev/null; then
            echo "Azure Data Studio window detected"
            break
        fi
        sleep 1
    done
fi

sleep 5

# Maximize window
WID=$(get_ads_windows | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss dialogs
echo "Dismissing dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="