#!/bin/bash
# Export script for chinook_loyalty_migration
# Inspects database state and exports findings to JSON

echo "=== Exporting Chinook Loyalty Migration Result ==="

DB_PATH="/home/ga/Documents/databases/chinook_loyalty.db"
CSV_PATH="/home/ga/Documents/exports/loyalty_summary.csv"
SQL_PATH="/home/ga/Documents/scripts/loyalty_migration.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- 1. Check File Existence & Timestamps ---
DB_EXISTS="false"
DB_MODIFIED="false"
if [ -f "$DB_PATH" ]; then
    DB_EXISTS="true"
    DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo 0)
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
fi

CSV_EXISTS="false"
if [ -f "$CSV_PATH" ]; then CSV_EXISTS="true"; fi

SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then SQL_EXISTS="true"; fi

# --- 2. Inspect Database Schema ---
HAS_COL_TIER="false"
HAS_COL_SPEND="false"
HAS_COL_JOIN="false"
HAS_TABLE_REWARDS="false"
REWARDS_SCHEMA_VALID="false"

if [ "$DB_EXISTS" = "true" ]; then
    # Check customers columns
    CUST_INFO=$(sqlite3 "$DB_PATH" "PRAGMA table_info(customers);" 2>/dev/null)
    if echo "$CUST_INFO" | grep -qi "LoyaltyTier"; then HAS_COL_TIER="true"; fi
    if echo "$CUST_INFO" | grep -qi "TotalSpend"; then HAS_COL_SPEND="true"; fi
    if echo "$CUST_INFO" | grep -qi "JoinDate"; then HAS_COL_JOIN="true"; fi
    
    # Check loyalty_rewards table
    REWARDS_INFO=$(sqlite3 "$DB_PATH" "PRAGMA table_info(loyalty_rewards);" 2>/dev/null)
    if [ -n "$REWARDS_INFO" ]; then 
        HAS_TABLE_REWARDS="true"
        # Check for required columns in rewards table
        if echo "$REWARDS_INFO" | grep -qi "Tier" && \
           echo "$REWARDS_INFO" | grep -qi "DiscountPercent" && \
           echo "$REWARDS_INFO" | grep -qi "Description"; then
            REWARDS_SCHEMA_VALID="true"
        fi
    fi
fi

# --- 3. Verify Data Content (The Heavy Lifting) ---
# We compare the agent's database content against our ground truth files computed in setup
TIER_MATCH_COUNT=0
SPEND_MATCH_COUNT=0
TOTAL_CUSTOMERS=0
REWARDS_ROW_COUNT=0
REWARDS_DATA_VALID="false"

if [ "$DB_EXISTS" = "true" ] && [ "$HAS_COL_TIER" = "true" ] && [ "$HAS_COL_SPEND" = "true" ]; then
    # Create a temp comparison script
    # We join the agent's live data with our ground truth CSV to count matches
    
    # Create a temporary table in memory or a scratch DB to do the comparison?
    # Simpler: Loop through ground truth and query the DB for specific IDs.
    # Since it's small (59 rows), a loop is fine.
    
    while IFS=, read -r cid expected_spend expected_tier; do
        if [ "$cid" == "CustomerId" ]; then continue; fi # Skip header
        
        TOTAL_CUSTOMERS=$((TOTAL_CUSTOMERS + 1))
        
        # Get agent's values
        AGENT_VALS=$(sqlite3 "$DB_PATH" "SELECT TotalSpend, LoyaltyTier FROM customers WHERE CustomerId=$cid;" 2>/dev/null)
        AGENT_SPEND=$(echo "$AGENT_VALS" | awk -F'|' '{print $1}')
        AGENT_TIER=$(echo "$AGENT_VALS" | awk -F'|' '{print $2}')
        
        # Verify Spend (allow 0.02 tolerance)
        DIFF=$(python3 -c "print(abs(float('$AGENT_SPEND') - float('$expected_spend')))" 2>/dev/null || echo "999")
        IS_CLOSE=$(python3 -c "print(1 if $DIFF < 0.05 else 0)" 2>/dev/null)
        
        if [ "$IS_CLOSE" -eq 1 ]; then
            SPEND_MATCH_COUNT=$((SPEND_MATCH_COUNT + 1))
        fi
        
        # Verify Tier (case-insensitive)
        if [ "${AGENT_TIER,,}" == "${expected_tier,,}" ]; then
            TIER_MATCH_COUNT=$((TIER_MATCH_COUNT + 1))
        fi
    done < /tmp/gt_customer_tiers.csv

    # Check Rewards Table Content
    if [ "$HAS_TABLE_REWARDS" = "true" ]; then
        REWARDS_ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM loyalty_rewards;" 2>/dev/null)
        
        # Verify specific discount rules (spot check)
        GOLD_DISC=$(sqlite3 "$DB_PATH" "SELECT DISTINCT DiscountPercent FROM loyalty_rewards WHERE Tier='Gold'" 2>/dev/null)
        SILVER_DISC=$(sqlite3 "$DB_PATH" "SELECT DISTINCT DiscountPercent FROM loyalty_rewards WHERE Tier='Silver'" 2>/dev/null)
        
        # Python check for float equality
        DISC_VALID=$(python3 -c "
try:
    g = float('$GOLD_DISC')
    s = float('$SILVER_DISC')
    print('true' if abs(g-15.0)<0.1 and abs(s-10.0)<0.1 else 'false')
except:
    print('false')
")
        if [ "$DISC_VALID" = "true" ]; then REWARDS_DATA_VALID="true"; fi
    fi
fi

# --- 4. Check DBeaver Connection ---
DBEAVER_CONN_FOUND="false"
CONFIG_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "ChinookLoyalty" "$CONFIG_FILE"; then
        DBEAVER_CONN_FOUND="true"
    fi
fi

# --- 5. Export JSON ---
GT_REWARD_ROWS=$(cat /tmp/gt_reward_count.txt 2>/dev/null || echo 0)

# Python to construct JSON safely
python3 -c "
import json
result = {
    'db_exists': $DB_EXISTS,
    'db_modified': $DB_MODIFIED,
    'csv_exists': $CSV_EXISTS,
    'sql_exists': $SQL_EXISTS,
    'schema': {
        'has_tier_col': $HAS_COL_TIER,
        'has_spend_col': $HAS_COL_SPEND,
        'has_join_col': $HAS_COL_JOIN,
        'has_rewards_table': $HAS_TABLE_REWARDS,
        'rewards_schema_valid': $REWARDS_SCHEMA_VALID
    },
    'data': {
        'total_customers': $TOTAL_CUSTOMERS,
        'spend_match_count': $SPEND_MATCH_COUNT,
        'tier_match_count': $TIER_MATCH_COUNT,
        'rewards_row_count': $REWARDS_ROW_COUNT,
        'rewards_row_expected': $GT_REWARD_ROWS,
        'rewards_data_valid': $REWARDS_DATA_VALID
    },
    'dbeaver_connection_found': $DBEAVER_CONN_FOUND
}
print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Copy to location accessible by copy_from_env (though /tmp is usually fine)
chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json