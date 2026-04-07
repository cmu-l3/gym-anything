#!/bin/bash
echo "=== Exporting workforce_classification_update result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png ga

echo "Extracting final database state..."

# We use docker exec to extract full tables as TSV for robust programmatic parsing in verifier.py.
# Using -B (batch) mode outputs tab-separated data with headers. Error output is redirected to /dev/null.

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT * FROM main_employmentstatus;" 2>/dev/null > /tmp/emp_status.tsv || true
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT * FROM main_users;" 2>/dev/null > /tmp/users.tsv || true
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT * FROM main_prefix;" 2>/dev/null > /tmp/prefixes.tsv || true
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT * FROM main_employees_summary;" 2>/dev/null > /tmp/emp_summary.tsv || true

# Update the counts JSON with current counts
CURRENT_STATUS_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_employmentstatus;" | tr -d '[:space:]')
CURRENT_PREFIX_COUNT=$(sentrifugo_db_query "SELECT COUNT(*) FROM main_prefix;" | tr -d '[:space:]')

# We inject the current counts into the existing JSON file safely
TEMP_JSON=$(mktemp /tmp/counts.XXXXXX.json)
jq ". + {\"current_status_count\": ${CURRENT_STATUS_COUNT:-0}, \"current_prefix_count\": ${CURRENT_PREFIX_COUNT:-0}}" /tmp/workforce_counts.json > "$TEMP_JSON" 2>/dev/null || true

if [ -f "$TEMP_JSON" ] && [ -s "$TEMP_JSON" ]; then
    cp "$TEMP_JSON" /tmp/workforce_counts.json
fi
rm -f "$TEMP_JSON"

chmod 666 /tmp/emp_status.tsv /tmp/users.tsv /tmp/prefixes.tsv /tmp/emp_summary.tsv /tmp/workforce_counts.json 2>/dev/null || true

echo "Database state exported to TSV files in /tmp/."
echo "=== Export Complete ==="