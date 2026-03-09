#!/bin/bash
echo "=== Exporting Schema Migration Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Schema Information
# We get the full database metadata which includes classes, properties, and indexes
echo "Fetching schema metadata..."
curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" > /tmp/schema_dump.json

# 3. Verify Data Backfill
# We run queries to count records matching expected values
echo "Verifying data backfill..."

# Restaurants: Check how many have Rating = 3.5
REST_RATING_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Restaurants WHERE Rating = 3.5" | jq '.result[0].count' 2>/dev/null || echo "0")
TOTAL_REST_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Restaurants" | jq '.result[0].count' 2>/dev/null || echo "0")

# Hotels: Check 5-star capacity
HOTEL_5STAR_CAP_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Hotels WHERE Stars = 5 AND Capacity = 500" | jq '.result[0].count' 2>/dev/null || echo "0")
TOTAL_HOTEL_5STAR_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Hotels WHERE Stars = 5" | jq '.result[0].count' 2>/dev/null || echo "0")

# Hotels: Check non-5-star capacity
HOTEL_OTHER_CAP_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Hotels WHERE Stars <> 5 AND Capacity = 200" | jq '.result[0].count' 2>/dev/null || echo "0")
TOTAL_HOTEL_OTHER_COUNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Hotels WHERE Stars <> 5" | jq '.result[0].count' 2>/dev/null || echo "0")

# 4. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
  "timestamp": $(date +%s),
  "schema": $(cat /tmp/schema_dump.json 2>/dev/null || echo "{}"),
  "data_stats": {
    "restaurants": {
      "total": $TOTAL_REST_COUNT,
      "with_correct_rating": $REST_RATING_COUNT
    },
    "hotels_5star": {
      "total": $TOTAL_HOTEL_5STAR_COUNT,
      "with_correct_capacity": $HOTEL_5STAR_CAP_COUNT
    },
    "hotels_other": {
      "total": $TOTAL_HOTEL_OTHER_COUNT,
      "with_correct_capacity": $HOTEL_OTHER_CAP_COUNT
    }
  }
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
echo "Export complete. Result size: $(stat -c %s /tmp/task_result.json) bytes"