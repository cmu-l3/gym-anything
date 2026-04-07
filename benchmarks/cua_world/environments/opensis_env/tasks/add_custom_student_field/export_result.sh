#!/bin/bash
set -e
echo "=== Exporting add_custom_student_field results ==="

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Export Categories
# We look for the 'Transportation' category specifically
echo "Exporting Categories..."
mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "SELECT * FROM custom_field_categories WHERE title LIKE '%Transportation%'" > /tmp/categories_export.txt 2>/dev/null || true

# 2. Export Fields
# We look for 'Bus Route Number' specifically
echo "Exporting Fields..."
mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "SELECT * FROM custom_fields WHERE title LIKE '%Bus Route%'" > /tmp/fields_export.txt 2>/dev/null || true

# 3. Get total counts for anti-gaming (did count increase?)
FINAL_CAT_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "SELECT COUNT(*) FROM custom_field_categories" 2>/dev/null || echo "0")
FINAL_FIELD_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "SELECT COUNT(*) FROM custom_fields" 2>/dev/null || echo "0")
INITIAL_CAT_COUNT=$(cat /tmp/initial_category_count.txt 2>/dev/null || echo "0")
INITIAL_FIELD_COUNT=$(cat /tmp/initial_field_count.txt 2>/dev/null || echo "0")

# 4. Construct JSON result
# Python script to parse the SQL output text files into JSON
python3 -c "
import json
import csv
import sys
import os

def parse_mysql_output(filepath):
    records = []
    if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
        try:
            with open(filepath, 'r') as f:
                reader = csv.DictReader(f, delimiter='\t')
                for row in reader:
                    records.append(row)
        except Exception as e:
            print(f'Error parsing {filepath}: {e}', file=sys.stderr)
    return records

categories = parse_mysql_output('/tmp/categories_export.txt')
fields = parse_mysql_output('/tmp/fields_export.txt')

result = {
    'categories': categories,
    'fields': fields,
    'counts': {
        'initial_cat': int('$INITIAL_CAT_COUNT'),
        'final_cat': int('$FINAL_CAT_COUNT'),
        'initial_field': int('$INITIAL_FIELD_COUNT'),
        'final_field': int('$FINAL_FIELD_COUNT')
    },
    'timestamp': '$(date +%s)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so agent/verifier can read it
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="