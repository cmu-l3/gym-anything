#!/bin/bash
# Setup for price_sync_merge task
echo "=== Setting up price_sync_merge task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Clean up and Prepare Database Objects
# ============================================================
echo "Preparing database schema..."

# Drop tables if they exist to ensure clean state
mssql_query "
    IF OBJECT_ID('Pricing.vw_MergeSummary', 'V') IS NOT NULL DROP VIEW Pricing.vw_MergeSummary;
    IF OBJECT_ID('Pricing.MergeAuditLog', 'U') IS NOT NULL DROP TABLE Pricing.MergeAuditLog;
    IF OBJECT_ID('Pricing.SupplierPriceUpdate', 'U') IS NOT NULL DROP TABLE Pricing.SupplierPriceUpdate;
    IF OBJECT_ID('Pricing.PriceMaster', 'U') IS NOT NULL DROP TABLE Pricing.PriceMaster;
    IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'Pricing') DROP SCHEMA Pricing;
" "AdventureWorks2022"

# Create Schema
mssql_query "CREATE SCHEMA Pricing;" "AdventureWorks2022"

# ============================================================
# 2. Generate Data (Deterministic Logic)
# ============================================================
echo "Generating dataset..."

# Create PriceMaster (The "Target")
# We exclude products with ID divisible by 10 to reserve them as "New" products for the MERGE
mssql_query "
    SELECT 
        ProductID, 
        Name as ProductName, 
        ListPrice, 
        StandardCost, 
        SellStartDate as LastUpdated
    INTO Pricing.PriceMaster
    FROM Production.Product
    WHERE ListPrice > 0 AND (ProductID % 10) != 0;
    
    ALTER TABLE Pricing.PriceMaster ADD CONSTRAINT PK_PriceMaster PRIMARY KEY (ProductID);
" "AdventureWorks2022"

# Create SupplierPriceUpdate (The "Source")
# Mix of:
# 1. Updates: Existing products (ID % 3 = 0) getting a 12% price HIKE
# 2. No Change: Existing products (ID % 3 = 1) keeping SAME price (Should NOT be updated/logged)
# 3. Inserts: New products (ID % 10 = 0) that don't exist in target
mssql_query "
    -- 1. Updates (Price Increases)
    SELECT 
        ProductID, 
        Name as ProductName, 
        CAST(ListPrice * 1.12 AS MONEY) as NewListPrice, 
        StandardCost
    INTO Pricing.SupplierPriceUpdate
    FROM Production.Product
    WHERE ListPrice > 0 AND (ProductID % 10) != 0 AND (ProductID % 3) = 0
    
    UNION ALL
    
    -- 2. No Changes (Same Price)
    SELECT 
        ProductID, 
        Name as ProductName, 
        ListPrice as NewListPrice, 
        StandardCost
    FROM Production.Product
    WHERE ListPrice > 0 AND (ProductID % 10) != 0 AND (ProductID % 3) = 1
    
    UNION ALL
    
    -- 3. Inserts (New Products)
    SELECT 
        ProductID, 
        Name as ProductName, 
        ListPrice as NewListPrice, 
        StandardCost
    FROM Production.Product
    WHERE ListPrice > 0 AND (ProductID % 10) = 0;
" "AdventureWorks2022"

# ============================================================
# 3. Calculate Expected Results for Verification
# ============================================================
echo "Calculating ground truth..."

# Calculate expected counts using SQL
EXPECTED_JSON=$(mssql_query "
    DECLARE @ExpectedUpdates INT = (
        SELECT COUNT(*) 
        FROM Pricing.SupplierPriceUpdate s
        JOIN Pricing.PriceMaster t ON s.ProductID = t.ProductID
        WHERE s.NewListPrice <> t.ListPrice
    );
    
    DECLARE @ExpectedInserts INT = (
        SELECT COUNT(*) 
        FROM Pricing.SupplierPriceUpdate s
        WHERE NOT EXISTS (SELECT 1 FROM Pricing.PriceMaster t WHERE t.ProductID = s.ProductID)
    );
    
    DECLARE @InitialMasterCount INT = (SELECT COUNT(*) FROM Pricing.PriceMaster);

    SELECT 
        FORMATMESSAGE('{\"expected_updates\": %d, \"expected_inserts\": %d, \"initial_master_count\": %d}', 
        @ExpectedUpdates, @ExpectedInserts, @InitialMasterCount);
" "AdventureWorks2022" | grep "{" | tr -d '\r')

echo "$EXPECTED_JSON" > /tmp/merge_expected.json
echo "Ground Truth: $EXPECTED_JSON"

# ============================================================
# 4. Azure Data Studio Setup
# ============================================================
echo "Launching Azure Data Studio..."

# Start ADS if not running
if ! pgrep -f "azuredatastudio" > /dev/null; then
    su - ga -c "DISPLAY=:1 /snap/bin/azuredatastudio > /tmp/ads.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "azure\|data studio"; then
            echo "ADS window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize
DISPLAY=:1 wmctrl -r "Azure Data Studio" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Connect to database via command palette shortcut (Anti-flaking)
# (Assuming agent knows how to connect, but we ensure window is focused)
DISPLAY=:1 wmctrl -a "Azure Data Studio" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="