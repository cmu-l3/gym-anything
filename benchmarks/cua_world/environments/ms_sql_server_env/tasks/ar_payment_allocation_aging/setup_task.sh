#!/bin/bash
echo "=== Setting up ar_payment_allocation_aging task ==="

source /workspace/scripts/task_utils.sh

# ============================================================
# Delete stale outputs BEFORE recording timestamp
# ============================================================
rm -f /home/ga/Documents/exports/ar_aging_report.csv 2>/dev/null
rm -f /tmp/ar_aging_result.json 2>/dev/null || sudo rm -f /tmp/ar_aging_result.json 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null
rm -f /tmp/task_final.png 2>/dev/null
rm -f /tmp/task_end_screenshot.png 2>/dev/null

# Record start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Clean up any existing AR schema objects (reverse dependency order)
# ============================================================
echo "Cleaning up previous AR schema objects..."

mssql_query "IF OBJECT_ID('AR.fn_AgingBuckets', 'IF') IS NOT NULL DROP FUNCTION AR.fn_AgingBuckets" "AdventureWorks2022"
mssql_query "IF OBJECT_ID('AR.vw_InvoiceOpenBalance', 'V') IS NOT NULL DROP VIEW AR.vw_InvoiceOpenBalance" "AdventureWorks2022"
mssql_query "IF OBJECT_ID('AR.usp_AllocatePayments', 'P') IS NOT NULL DROP PROCEDURE AR.usp_AllocatePayments" "AdventureWorks2022"
mssql_query "IF OBJECT_ID('AR.PaymentAllocation', 'U') IS NOT NULL DROP TABLE AR.PaymentAllocation" "AdventureWorks2022"
mssql_query "IF OBJECT_ID('AR.PaymentLedger', 'U') IS NOT NULL DROP TABLE AR.PaymentLedger" "AdventureWorks2022"
mssql_query "IF SCHEMA_ID('AR') IS NOT NULL DROP SCHEMA AR" "AdventureWorks2022"

# ============================================================
# Create AR schema and seed PaymentLedger
# ============================================================
echo "Creating AR schema and seeding PaymentLedger..."

mssql_query "CREATE SCHEMA AR" "AdventureWorks2022"

mssql_query "CREATE TABLE AR.PaymentLedger (PaymentID INT IDENTITY(1,1) PRIMARY KEY, CustomerID INT NOT NULL, PaymentDate DATE NOT NULL, Amount DECIMAL(18,2) NOT NULL, PaymentMethod VARCHAR(20) NOT NULL)" "AdventureWorks2022"

# Seed payment data from actual SalesOrderHeader rows.
# Deterministic formula based on SalesOrderID % 20:
#   0-13  (70%): Full payment, Amount = TotalDue
#   14-16 (15%): Two split payments (60% + 40%)
#   17-18 (10%): Late partial payment (50% of TotalDue)
#   19     (5%): No payment (fully unpaid invoices)
echo "Seeding full payments (70% of orders)..."
mssql_query "INSERT INTO AR.PaymentLedger (CustomerID, PaymentDate, Amount, PaymentMethod) SELECT CustomerID, DATEADD(day, (SalesOrderID % 45) + 5, OrderDate), TotalDue, CASE SalesOrderID % 4 WHEN 0 THEN 'Check' WHEN 1 THEN 'Wire' WHEN 2 THEN 'CreditCard' WHEN 3 THEN 'ACH' END FROM Sales.SalesOrderHeader WHERE SalesOrderID % 20 BETWEEN 0 AND 13 AND TotalDue > 0" "AdventureWorks2022"

echo "Seeding split payments - part 1 (15% of orders, 60% amount)..."
mssql_query "INSERT INTO AR.PaymentLedger (CustomerID, PaymentDate, Amount, PaymentMethod) SELECT CustomerID, DATEADD(day, 25, OrderDate), ROUND(TotalDue * 0.6, 2), 'Wire' FROM Sales.SalesOrderHeader WHERE SalesOrderID % 20 BETWEEN 14 AND 16 AND TotalDue > 0" "AdventureWorks2022"

echo "Seeding split payments - part 2 (remaining 40%)..."
mssql_query "INSERT INTO AR.PaymentLedger (CustomerID, PaymentDate, Amount, PaymentMethod) SELECT CustomerID, DATEADD(day, 55, OrderDate), TotalDue - ROUND(TotalDue * 0.6, 2), 'ACH' FROM Sales.SalesOrderHeader WHERE SalesOrderID % 20 BETWEEN 14 AND 16 AND TotalDue > 0" "AdventureWorks2022"

echo "Seeding late partial payments (10% of orders, 50% amount)..."
mssql_query "INSERT INTO AR.PaymentLedger (CustomerID, PaymentDate, Amount, PaymentMethod) SELECT CustomerID, DATEADD(day, 120, OrderDate), ROUND(TotalDue * 0.5, 2), 'Check' FROM Sales.SalesOrderHeader WHERE SalesOrderID % 20 BETWEEN 17 AND 18 AND TotalDue > 0" "AdventureWorks2022"

# Note: SalesOrderID % 20 = 19 gets NO payment rows (5% fully unpaid)

# ============================================================
# Record reference values for verification
# ============================================================
echo "Recording reference values..."

REF_TOTAL_PAYMENTS=$(mssql_query "
    SELECT CAST(SUM(Amount) AS DECIMAL(18,2)) FROM AR.PaymentLedger
" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')

REF_PAYMENT_ROW_COUNT=$(mssql_query "
    SELECT COUNT(*) FROM AR.PaymentLedger
" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')

REF_TOTAL_INVOICES=$(mssql_query "
    SELECT COUNT(*) FROM Sales.SalesOrderHeader
" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')

REF_TOTAL_TOTALDUE=$(mssql_query "
    SELECT CAST(SUM(TotalDue) AS DECIMAL(18,2)) FROM Sales.SalesOrderHeader
" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')

REF_DISTINCT_CUSTOMERS=$(mssql_query "
    SELECT COUNT(DISTINCT CustomerID) FROM AR.PaymentLedger
" "AdventureWorks2022" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n')

cat > /tmp/initial_state.txt << EOF
Total_Payments: ${REF_TOTAL_PAYMENTS:-0}
Payment_Row_Count: ${REF_PAYMENT_ROW_COUNT:-0}
Total_Invoices: ${REF_TOTAL_INVOICES:-0}
Total_TotalDue: ${REF_TOTAL_TOTALDUE:-0}
Distinct_Customers: ${REF_DISTINCT_CUSTOMERS:-0}
EOF

echo "Reference values recorded:"
cat /tmp/initial_state.txt

# ============================================================
# Create output directories
# ============================================================
echo "Creating output directories..."
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports 2>/dev/null || true
chmod 755 /home/ga/Documents/exports

# ============================================================
# Write credentials file to Desktop
# ============================================================
echo "Creating credentials file..."
cat > /home/ga/Desktop/SQL_CREDENTIALS.txt << 'CREDS'
=== SQL Server Connection Details ===

Server: localhost
Username: sa
Password: GymAnything#2024
Database: AdventureWorks2022

Quick-start in terminal:
  mssql-query "YOUR SQL HERE" AdventureWorks2022
CREDS
chown ga:ga /home/ga/Desktop/SQL_CREDENTIALS.txt 2>/dev/null || true

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
