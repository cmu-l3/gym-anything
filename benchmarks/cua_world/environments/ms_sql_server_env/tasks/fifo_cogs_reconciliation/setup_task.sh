#!/bin/bash
# Setup for fifo_cogs_reconciliation task
echo "=== Setting up FIFO COGS Reconciliation Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Clean up Previous State
# ============================================================
echo "Cleaning up database..."
mssql_query "
    IF OBJECT_ID('Accounting.FIFOAllocation', 'U') IS NOT NULL DROP TABLE Accounting.FIFOAllocation;
    IF OBJECT_ID('Inventory.InputBatches', 'U') IS NOT NULL DROP TABLE Inventory.InputBatches;
    IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Accounting') DROP SCHEMA Accounting;
    IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Inventory') DROP SCHEMA Inventory;
" "AdventureWorks2022"

# ============================================================
# 2. Prepare Data
# ============================================================
echo "Seeding Inventory Data..."

# Create Inventory Schema
mssql_query "CREATE SCHEMA Inventory;" "AdventureWorks2022"

# Create InputBatches Table
mssql_query "
    CREATE TABLE Inventory.InputBatches (
        BatchID INT PRIMARY KEY,
        ProductID INT,
        BatchDate DATE,
        Quantity INT,
        UnitCost MONEY
    );
" "AdventureWorks2022"

# Seed Data
# Strategy:
# Product 707 demand in Q3 2012 is roughly 300-400 units (based on standard AdventureWorks2022 data).
# We will create batches that force splits.
# Batch 101: 120 units @ $10.00 (Should be fully consumed)
# Batch 102: 150 units @ $12.50 (Should be fully consumed)
# Batch 103: 100 units @ $11.00 (Likely split or partial)
# Batch 104: 500 units @ $13.00 (Buffer to cover remainder)

mssql_query "
    INSERT INTO Inventory.InputBatches (BatchID, ProductID, BatchDate, Quantity, UnitCost)
    VALUES 
    (101, 707, '2012-01-01', 120, 10.00),
    (102, 707, '2012-03-15', 150, 12.50),
    (103, 707, '2012-05-20', 100, 11.00),
    (104, 707, '2012-06-30', 500, 13.00);
" "AdventureWorks2022"

echo "Data seeding complete."

# ============================================================
# 3. Launch Azure Data Studio
# ============================================================
echo "Launching Azure Data Studio..."

if ! pgrep -f "azuredatastudio" > /dev/null; then
    ADS_CMD="/snap/bin/azuredatastudio"
    [ -x "$ADS_CMD" ] || ADS_CMD="azuredatastudio"
    
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/ads.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then
            echo "ADS window detected."
            break
        fi
        sleep 1
    done
fi

# Focus and maximize
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="