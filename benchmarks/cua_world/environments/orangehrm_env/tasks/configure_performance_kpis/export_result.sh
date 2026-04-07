#!/bin/bash
echo "=== Exporting configure_performance_kpis result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_kpi_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Final State
# We fetch all active KPIs created/active to verify details in Python
# We join with job_title table to get readable names
echo "Querying KPI data..."

# Create a temporary SQL file to handle the join cleanly
cat > /tmp/query_kpis.sql << SQL
SELECT 
    k.kpi_indicators, 
    j.job_title, 
    k.min_rating, 
    k.max_rating
FROM ohrm_kpi k
JOIN ohrm_job_title j ON k.job_title_code = j.id
WHERE k.is_deleted = 0;
SQL

# Execute query and format as JSON array of objects
# Output format: "KPI Name"\t"Job Title"\t"Min"\t"Max"
# We use jq to construct the JSON carefully
KPI_DATA_RAW=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N < /tmp/query_kpis.sql 2>/dev/null)

# Convert raw tab-separated output to JSON
KPI_JSON_ARRAY=$(echo "$KPI_DATA_RAW" | jq -R -s '
  split("\n") | map(select(length > 0)) | map(
    split("\t") | {
      name: .[0],
      job_title: .[1],
      min_rating: .[2] | tonumber,
      max_rating: .[3] | tonumber
    }
  )
')

# Get final count
FINAL_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_kpi WHERE is_deleted=0;" 2>/dev/null | tr -d '[:space:]')

# 4. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "final_count": ${FINAL_COUNT:-0},
    "kpi_records": ${KPI_JSON_ARRAY:-[]},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" "/tmp/query_kpis.sql"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="