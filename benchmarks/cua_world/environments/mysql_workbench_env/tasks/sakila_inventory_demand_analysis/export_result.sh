#!/bin/bash
# Export script for sakila_inventory_demand_analysis

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check CSV Export
CSV_FILE="/home/ga/Documents/exports/high_utilization_films.csv"
CSV_EXISTS="false"
CSV_SIZE=0
CSV_MTIME=0
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_FILE")
    CSV_MTIME=$(stat -c%Y "$CSV_FILE")
fi

# 3. Check Database Objects (View Existence & Definition)
VIEW_NAME="v_july_2005_utilization"
VIEW_EXISTS="false"
VIEW_DEF=""

# Check if view exists
VIEW_CHECK=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT COUNT(*) FROM information_schema.VIEWS 
    WHERE TABLE_SCHEMA = 'sakila' AND TABLE_NAME = '$VIEW_NAME';
" 2>/dev/null)

if [ "$VIEW_CHECK" -eq "1" ]; then
    VIEW_EXISTS="true"
    # Get definition to check for logic (keywords like '24', 'NULL', 'inventory', 'rental')
    VIEW_DEF=$(mysql -u root -p'GymAnything#2024' -N -e "
        SELECT VIEW_DEFINITION FROM information_schema.VIEWS 
        WHERE TABLE_SCHEMA = 'sakila' AND TABLE_NAME = '$VIEW_NAME';
    " 2>/dev/null)
fi

# 4. Generate Ground Truth Data
# We calculate the metrics using a trusted query to compare against agent's CSV
# Note: We use the same business rules: 
#   - July 2005
#   - Exclude return < rental
#   - NULL return = 24h (86400s)

echo "Generating ground truth..."
cat > /tmp/ground_truth_query.sql << SQL
SELECT 
    f.title,
    COUNT(DISTINCT i.inventory_id) as inventory_count,
    ROUND(
        (
            SUM(
                CASE 
                    WHEN r.return_date IS NULL THEN 24 -- Open rental rule
                    WHEN r.return_date < r.rental_date THEN 0 -- Bad data rule (exclude)
                    ELSE TIMESTAMPDIFF(HOUR, r.rental_date, r.return_date)
                END
            ) 
            / 
            (COUNT(DISTINCT i.inventory_id) * 31 * 24) -- Capacity
        ) * 100
    , 2) as utilization_pct
FROM film f
JOIN inventory i ON f.film_id = i.film_id
JOIN rental r ON i.inventory_id = r.inventory_id
WHERE r.rental_date >= '2005-07-01 00:00:00' 
  AND r.rental_date <= '2005-07-31 23:59:59'
  AND (r.return_date IS NULL OR r.return_date >= r.rental_date) -- Filter bad data from SUM? 
  -- Actually, the task said "Treat these as invalid and exclude". 
  -- The CASE above handles the sum logic, but let's be precise.
  -- If we filter in WHERE, we lose the record entirely. 
  -- If we treat as 0 in SUM, we keep the record count? Task implies affecting the 'total_rented_hours'.
  -- Let's stick to the CASE WHEN ... THEN 0 approach for safety.
GROUP BY f.film_id, f.title
ORDER BY utilization_pct DESC
LIMIT 30;
SQL

# Execute Ground Truth
# Output format: JSON-like or CSV for python parsing
mysql -u root -p'GymAnything#2024' sakila < /tmp/ground_truth_query.sql > /tmp/ground_truth.txt 2>/dev/null

# 5. Export User View Data (for logic verification)
# We query the user's view to see if it matches our expectations for specific test cases
if [ "$VIEW_EXISTS" = "true" ]; then
    mysql -u root -p'GymAnything#2024' sakila -e "SELECT * FROM $VIEW_NAME ORDER BY utilization_pct DESC LIMIT 30;" > /tmp/user_view_output.txt 2>/dev/null
else
    touch /tmp/user_view_output.txt
fi

# 6. Read User CSV content
if [ "$CSV_EXISTS" = "true" ]; then
    cat "$CSV_FILE" > /tmp/user_csv_content.txt
else
    touch /tmp/user_csv_content.txt
fi

# 7. Package everything into JSON
# We'll use Python to construct the JSON safely to avoid escaping issues
python3 -c "
import json
import os
import time

def read_file(path):
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    return ''

result = {
    'view_exists': '$VIEW_EXISTS' == 'true',
    'view_definition': read_file('/tmp/ground_truth_query.sql'), # Placeholder, we rely on output comp
    'csv_exists': '$CSV_EXISTS' == 'true',
    'csv_mtime': int('$CSV_MTIME'),
    'task_start': int('$TASK_START'),
    'ground_truth_raw': read_file('/tmp/ground_truth.txt'),
    'user_view_raw': read_file('/tmp/user_view_output.txt'),
    'user_csv_raw': read_file('/tmp/user_csv_content.txt')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

echo "Result exported to /tmp/task_result.json"