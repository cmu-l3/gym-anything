#!/bin/bash
# Export script for sakila_geospatial_customer_rebalancing

echo "=== Exporting Geospatial Task Results ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check if staging table exists and has data
STAGING_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM geo_staging;" 2>/dev/null || echo "0")

# 2. Check how many addresses have been updated (non-zero coordinates)
# Assuming default was POINT(0 0) or NULL.
# We check X(location) != 0 OR Y(location) != 0
ADDRESS_UPDATED_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM address 
    WHERE location IS NOT NULL 
    AND (ST_X(location) != 0 OR ST_Y(location) != 0);
" 2>/dev/null || echo "0")

# 3. Check Customer Store Assignments
# Store 1 should be Americas/Europe
# Store 2 should be Asia/Oceania
# We can sample a few known customers to verify logic
# Mary Smith (ID 1) -> Sasebo, Japan -> Should be Store 2
STORE_MARY=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT store_id FROM customer WHERE customer_id = 1;" 2>/dev/null || echo "0")
# Patricia Johnson (ID 2) -> San Bernardino, USA -> Should be Store 1
STORE_PATRICIA=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT store_id FROM customer WHERE customer_id = 2;" 2>/dev/null || echo "0")
# Elizabeth Brown (ID 5) -> Nantou, Taiwan -> Should be Store 2
STORE_ELIZABETH=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT store_id FROM customer WHERE customer_id = 5;" 2>/dev/null || echo "0")
# Richard Mccrary (ID 9) -> Cianjur, Indonesia -> Should be Store 2
STORE_RICHARD=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT store_id FROM customer WHERE customer_id = 9;" 2>/dev/null || echo "0")
# Linda Williams (ID 3) -> Athenai, Greece -> Dist(Canada)~8600km, Dist(Aus)~15000km -> Store 1
STORE_LINDA=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT store_id FROM customer WHERE customer_id = 3;" 2>/dev/null || echo "0")

# 4. Check CSV Export
CSV_EXISTS="false"
CSV_ROWS=0
OUTPUT_FILE="/home/ga/Documents/exports/logistics_optimization.csv"
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# 5. Get distribution stats
COUNT_STORE_1=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer WHERE store_id=1;" 2>/dev/null || echo "0")
COUNT_STORE_2=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer WHERE store_id=2;" 2>/dev/null || echo "0")

cat > /tmp/geospatial_result.json << EOF
{
    "staging_rows": $STAGING_COUNT,
    "address_updated_count": $ADDRESS_UPDATED_COUNT,
    "store_mary_japan": $STORE_MARY,
    "store_patricia_usa": $STORE_PATRICIA,
    "store_elizabeth_taiwan": $STORE_ELIZABETH,
    "store_richard_indonesia": $STORE_RICHARD,
    "store_linda_greece": $STORE_LINDA,
    "count_store_1": $COUNT_STORE_1,
    "count_store_2": $COUNT_STORE_2,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "task_start": $TASK_START
}
EOF

echo "Result: Staging=$STAGING_COUNT Updated=$ADDRESS_UPDATED_COUNT CSV=$CSV_ROWS Store1=$COUNT_STORE_1 Store2=$COUNT_STORE_2"
echo "=== Export Complete ==="