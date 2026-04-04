#!/bin/bash
# Export script for chinook_genre_target_import
# Verifies database state and analyzes exported files

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_CSV="/home/ga/Documents/exports/genre_variance_report.csv"
SQL_SCRIPT="/home/ga/Documents/scripts/genre_variance_analysis.sql"
TARGET_CSV="/home/ga/Documents/imports/genre_sales_targets.csv"
GROUND_TRUTH_FILE="/tmp/ground_truth_variance.json"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- Check 1: DBeaver Connection 'ChinookImport' ---
CONNECTION_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -q "ChinookImport" "$DBEAVER_CONFIG"; then
        CONNECTION_EXISTS="true"
    fi
fi

# --- Check 2: Database Table 'genre_sales_targets' ---
TABLE_EXISTS="false"
DB_ROW_COUNT=0
TARGET_CSV_ROWS=0

if [ -f "$TARGET_CSV" ]; then
    # Subtract header
    TARGET_CSV_ROWS=$(($(wc -l < "$TARGET_CSV") - 1))
fi

if [ -f "$DB_PATH" ]; then
    # Check if table exists
    if sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='genre_sales_targets';" | grep -q "genre_sales_targets"; then
        TABLE_EXISTS="true"
        # Get row count
        DB_ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM genre_sales_targets;" 2>/dev/null || echo 0)
    fi
fi

# --- Check 3: SQL Script Existence ---
SQL_SCRIPT_EXISTS="false"
if [ -f "$SQL_SCRIPT" ]; then
    SQL_SCRIPT_EXISTS="true"
fi

# --- Check 4: Export CSV Validation ---
# We use Python to parse the user's export and compare against Ground Truth
python3 -c "
import csv
import json
import sys
import os

export_path = '$EXPORT_CSV'
gt_path = '$GROUND_TRUTH_FILE'

result = {
    'export_exists': False,
    'columns_valid': False,
    'row_count_valid': False,
    'data_accuracy': 0.0, # Percentage of rows matching ground truth
    'columns_found': []
}

if os.path.exists(export_path):
    result['export_exists'] = True
    try:
        # Load Ground Truth
        with open(gt_path, 'r') as f:
            gt_data = json.load(f)
            # Index GT by Genre+Year for fast lookup
            gt_map = {f\"{item['GenreName']}_{item['Year']}\": item for item in gt_data}

        with open(export_path, 'r') as f:
            reader = csv.DictReader(f)
            result['columns_found'] = reader.fieldnames
            
            # Check required columns (case-insensitive)
            required = set(['genre', 'year', 'target', 'actual', 'variance', 'pct'])
            # Normalize found columns for checking
            found_normalized = set()
            for col in (reader.fieldnames or []):
                lower = col.lower()
                if 'genre' in lower: found_normalized.add('genre')
                if 'year' in lower: found_normalized.add('year')
                if 'target' in lower: found_normalized.add('target')
                if 'actual' in lower: found_normalized.add('actual')
                if 'variance' in lower and 'pct' not in lower: found_normalized.add('variance')
                if 'pct' in lower or 'percent' in lower: found_normalized.add('pct')
            
            if required.issubset(found_normalized):
                result['columns_valid'] = True

            # Validate Data
            matches = 0
            total_rows = 0
            
            for row in reader:
                total_rows += 1
                
                # Extract keys flexibly
                genre_key = next((k for k in row.keys() if 'genre' in k.lower()), None)
                year_key = next((k for k in row.keys() if 'year' in k.lower()), None)
                var_key = next((k for k in row.keys() if 'variance' in k.lower() and 'pct' not in k.lower()), None)
                
                if genre_key and year_key and var_key:
                    g_val = row[genre_key]
                    y_val = row[year_key]
                    v_val = row[var_key]
                    
                    lookup_key = f\"{g_val}_{y_val}\"
                    if lookup_key in gt_map:
                        gt_item = gt_map[lookup_key]
                        
                        try:
                            # Allow small floating point tolerance
                            user_var = float(v_val)
                            gt_var = float(gt_item['Variance'])
                            if abs(user_var - gt_var) < 0.1:
                                matches += 1
                        except ValueError:
                            pass
            
            if total_rows > 0:
                result['data_accuracy'] = matches / total_rows
            
            # Check row count roughly matches GT (GT has all possible, user might filter)
            # We expect at least 80% of GT rows
            if total_rows >= len(gt_data) * 0.8:
                result['row_count_valid'] = True
                
            result['user_row_count'] = total_rows
            result['gt_row_count'] = len(gt_data)

    except Exception as e:
        result['error'] = str(e)

# Output result to JSON file
with open('/tmp/py_validation.json', 'w') as f:
    json.dump(result, f)
"

# Combine shell and python results
cat > /tmp/task_result.json << EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "db_row_count": $DB_ROW_COUNT,
    "target_csv_rows": $TARGET_CSV_ROWS,
    "sql_script_exists": $SQL_SCRIPT_EXISTS,
    "task_start_time": $(cat /tmp/task_start_time 2>/dev/null || echo 0),
    "export_timestamp": $(date +%s),
    "validation": $(cat /tmp/py_validation.json 2>/dev/null || echo "{}")
}
EOF

# Clean up temp
rm -f /tmp/py_validation.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="