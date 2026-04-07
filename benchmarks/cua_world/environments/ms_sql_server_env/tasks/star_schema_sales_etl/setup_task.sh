#!/bin/bash
echo "=== Setting up star_schema_sales_etl task ==="

source /workspace/scripts/task_utils.sh

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/Documents/exports/dw_revenue_summary.csv 2>/dev/null
rm -f /tmp/star_schema_result.json 2>/dev/null || sudo rm -f /tmp/star_schema_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null
rm -f /tmp/task_final.png 2>/dev/null
rm -f /tmp/task_end_screenshot.png 2>/dev/null

# Record start time
date +%s > /tmp/task_start_time.txt

# ── Clean up any existing DW schema objects (reverse dependency order) ────────
mssql_query "
IF SCHEMA_ID('DW') IS NOT NULL
BEGIN
    DECLARE @sql NVARCHAR(MAX) = '';

    -- Drop foreign keys first
    SELECT @sql = @sql + 'ALTER TABLE [DW].' + QUOTENAME(OBJECT_NAME(parent_object_id))
        + ' DROP CONSTRAINT ' + QUOTENAME(name) + '; '
    FROM sys.foreign_keys
    WHERE schema_id = SCHEMA_ID('DW');

    IF LEN(@sql) > 0 EXEC sp_executesql @sql;

    -- Drop tables
    SET @sql = '';
    SELECT @sql = @sql + 'DROP TABLE [DW].' + QUOTENAME(name) + '; '
    FROM sys.objects
    WHERE schema_id = SCHEMA_ID('DW') AND type = 'U';

    IF LEN(@sql) > 0 EXEC sp_executesql @sql;

    -- Drop procedures
    SET @sql = '';
    SELECT @sql = @sql + 'DROP PROCEDURE [DW].' + QUOTENAME(name) + '; '
    FROM sys.objects
    WHERE schema_id = SCHEMA_ID('DW') AND type = 'P';

    IF LEN(@sql) > 0 EXEC sp_executesql @sql;

    -- Drop views
    SET @sql = '';
    SELECT @sql = @sql + 'DROP VIEW [DW].' + QUOTENAME(name) + '; '
    FROM sys.objects
    WHERE schema_id = SCHEMA_ID('DW') AND type = 'V';

    IF LEN(@sql) > 0 EXEC sp_executesql @sql;

    -- Drop schema
    DROP SCHEMA DW;
END
" "AdventureWorks2022"

# ── Ensure export directory exists ────────────────────────────────────────────
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents 2>/dev/null || true

# ── Create credentials file on Desktop ────────────────────────────────────────
cat > /home/ga/Desktop/SQL_CREDENTIALS.txt << 'CRED_EOF'
=== SQL Server Connection ===
Server:   localhost
Username: sa
Password: GymAnything#2024
Database: AdventureWorks2022
Trust Server Certificate: True

Terminal shortcut:
  mssql-query "YOUR SQL HERE" AdventureWorks2022
CRED_EOF
chown ga:ga /home/ga/Desktop/SQL_CREDENTIALS.txt 2>/dev/null || true

# ── Verify SQL Server is running ──────────────────────────────────────────────
if ! mssql_is_running; then
    echo "WARNING: SQL Server may not be running"
fi

# ── Record reference values for verification ──────────────────────────────────
REF_LINETOTAL=$(mssql_query "SELECT CAST(SUM(LineTotal) AS DECIMAL(18,2)) FROM Sales.SalesOrderDetail" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')
REF_TAX=$(mssql_query "SELECT CAST(SUM(TaxAmt) AS DECIMAL(18,2)) FROM Sales.SalesOrderHeader" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')
REF_FREIGHT=$(mssql_query "SELECT CAST(SUM(Freight) AS DECIMAL(18,2)) FROM Sales.SalesOrderHeader" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')
REF_PRODUCTS=$(mssql_query "SELECT COUNT(*) FROM Production.Product" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')
REF_CUSTOMERS=$(mssql_query "SELECT COUNT(*) FROM Sales.Customer" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')
REF_LINEITEMS=$(mssql_query "SELECT COUNT(*) FROM Sales.SalesOrderDetail" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')
REF_NULL_SUBCAT=$(mssql_query "SELECT COUNT(*) FROM Production.Product WHERE ProductSubcategoryID IS NULL" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')
REF_STORE_ONLY=$(mssql_query "SELECT COUNT(*) FROM Sales.Customer WHERE PersonID IS NULL AND StoreID IS NOT NULL" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')

cat > /tmp/initial_state.txt << EOF
Reference_LineTotal: ${REF_LINETOTAL:-0}
Reference_Tax: ${REF_TAX:-0}
Reference_Freight: ${REF_FREIGHT:-0}
Product_Count: ${REF_PRODUCTS:-0}
Customer_Count: ${REF_CUSTOMERS:-0}
LineItem_Count: ${REF_LINEITEMS:-0}
NULL_Subcategory_Products: ${REF_NULL_SUBCAT:-0}
Store_Only_Customers: ${REF_STORE_ONLY:-0}
EOF

echo "Reference values recorded:"
cat /tmp/initial_state.txt

# ── Remove untrusted desktop shortcut (prevents blocking GNOME dialog) ────────
rm -f /home/ga/Desktop/AzureDataStudio.desktop 2>/dev/null || true

# ── Launch ADS if not running ─────────────────────────────────────────────────
if ! pgrep -f "azuredatastudio" > /dev/null; then
    ADS_CMD="/snap/bin/azuredatastudio"
    [ -x "$ADS_CMD" ] || ADS_CMD="azuredatastudio"
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/ads.log 2>&1 &"
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then break; fi
        sleep 1
    done
fi

# ── Focus and maximize ADS window ─────────────────────────────────────────────
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# ── Dismiss startup dialogs ───────────────────────────────────────────────────
DISPLAY=:1 xdotool key Tab Tab Return       # OS keyring dialog
sleep 1
DISPLAY=:1 xdotool mousemove 1879 1015 click 1  # Preview features "No"
sleep 1
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 540 click 1    # Click main editor area
sleep 0.5

# ── Establish connection via Command Palette ──────────────────────────────────
DISPLAY=:1 xdotool key F1
sleep 1
DISPLAY=:1 xdotool type 'new connection'
sleep 1
DISPLAY=:1 xdotool key Return
sleep 2

# Fill connection fields (1920x1080 coordinates)
DISPLAY=:1 xdotool mousemove 1740 690 click 1; sleep 0.3   # Server field
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type 'localhost'; sleep 0.3
DISPLAY=:1 xdotool mousemove 1740 755 click 1; sleep 0.3   # User name
DISPLAY=:1 xdotool type 'sa'; sleep 0.3
DISPLAY=:1 xdotool mousemove 1740 785 click 1; sleep 0.3   # Password
DISPLAY=:1 xdotool type 'GymAnything#2024'; sleep 0.3
DISPLAY=:1 xdotool mousemove 1740 905 click 1; sleep 0.5   # Trust cert dropdown
DISPLAY=:1 xdotool key t Return; sleep 0.5                   # Select "True"
DISPLAY=:1 xdotool mousemove 1770 1049 click 1              # Connect button
sleep 5

# ── Wait for connection with retry ────────────────────────────────────────────
CONNECTION_ESTABLISHED=false
for i in $(seq 1 15); do
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure" | head -1)
    if echo "$TITLE" | grep -qi "localhost.*Azure"; then
        CONNECTION_ESTABLISHED=true
        break
    fi
    if [ "$i" -eq 8 ]; then
        DISPLAY=:1 xdotool key Return
    fi
    sleep 1
done

# ── Retry connection if needed ────────────────────────────────────────────────
if [ "$CONNECTION_ESTABLISHED" = "false" ]; then
    echo "First connection attempt failed, retrying..."
    DISPLAY=:1 xdotool key Escape
    sleep 1
    DISPLAY=:1 xdotool key F1
    sleep 1
    DISPLAY=:1 xdotool type 'new connection'
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 2
    DISPLAY=:1 xdotool mousemove 1740 690 click 1; sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type 'localhost'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 755 click 1; sleep 0.3
    DISPLAY=:1 xdotool type 'sa'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 785 click 1; sleep 0.3
    DISPLAY=:1 xdotool type 'GymAnything#2024'; sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 905 click 1; sleep 0.5
    DISPLAY=:1 xdotool key t Return; sleep 0.5
    DISPLAY=:1 xdotool mousemove 1770 1049 click 1
    sleep 8
fi

# ── Open new query editor ─────────────────────────────────────────────────────
DISPLAY=:1 xdotool key F1
sleep 0.5
DISPLAY=:1 xdotool type 'new query'
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 2

# Clear editor
DISPLAY=:1 xdotool mousemove 600 400 click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a Delete
sleep 0.5

# Type helpful connection info into the editor
DISPLAY=:1 xdotool type --delay 20 '-- Connected to AdventureWorks2022 (sa / GymAnything#2024)'
DISPLAY=:1 xdotool key Return
DISPLAY=:1 xdotool type --delay 20 '-- Terminal: mssql-query "SELECT 1" AdventureWorks2022'
DISPLAY=:1 xdotool key Return Return
sleep 0.5

# Final dialog cleanup
DISPLAY=:1 xdotool mousemove 1889 917 click 1   # Close preview X button
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 400 click 1
sleep 0.5

# ── Take initial screenshot ───────────────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Setup complete. ADS connected with query editor open. ==="
