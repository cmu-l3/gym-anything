#!/bin/bash
set -e
echo "=== Exporting create_journal_entry results ==="

source /workspace/scripts/task_utils.sh

# Variables
TENANT_SCHEMA=$(cat /tmp/ekylibre_tenant_schema.txt 2>/dev/null || echo "demo")
INITIAL_COUNT=$(cat /tmp/initial_journal_entry_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the results
# We construct a complex JSON object using PSQL's JSON functions to get the entry and its lines
echo "Querying database for new journal entry..."

# SQL query to find the entry created during the task window or matching specific criteria
# We look for an entry printed on 2017-06-15 created after task start
SQL_QUERY="
SET search_path TO \"$TENANT_SCHEMA\", public;
WITH target_entry AS (
  SELECT je.id, je.printed_on, je.created_at, je.updated_at
  FROM journal_entries je
  WHERE je.printed_on = '2017-06-15'
    AND je.created_at >= to_timestamp($TASK_START_TIME)
  ORDER BY je.created_at DESC
  LIMIT 1
),
entry_lines AS (
  SELECT 
    jei.entry_id,
    json_agg(json_build_object(
      'name', jei.name,
      'debit', jei.real_debit,
      'credit', jei.real_credit,
      'account_number', a.number,
      'account_name', a.name
    )) as lines
  FROM journal_entry_items jei
  JOIN accounts a ON a.id = jei.account_id
  WHERE jei.entry_id IN (SELECT id FROM target_entry)
  GROUP BY jei.entry_id
)
SELECT json_build_object(
  'initial_count', $INITIAL_COUNT,
  'final_count', (SELECT COUNT(*) FROM journal_entries),
  'entry_found', CASE WHEN EXISTS (SELECT 1 FROM target_entry) THEN true ELSE false END,
  'entry', (
    SELECT json_build_object(
      'id', te.id,
      'printed_on', te.printed_on,
      'created_at', te.created_at,
      'lines', el.lines
    )
    FROM target_entry te
    LEFT JOIN entry_lines el ON el.entry_id = te.id
  )
);"

# Execute query and capture output
JSON_RESULT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "$SQL_QUERY" 2>/dev/null || echo "{}")

# Save to temp file with proper permissions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$JSON_RESULT" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Exported JSON data:"
head -n 20 /tmp/task_result.json

echo "=== Export complete ==="