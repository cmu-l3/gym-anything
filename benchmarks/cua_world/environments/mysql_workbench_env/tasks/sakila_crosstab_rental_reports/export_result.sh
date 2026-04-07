#!/bin/bash
echo "=== Exporting sakila_crosstab_rental_reports results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/Documents/exports"
DB_USER="ga"
DB_PASS="password123"
DB_NAME="sakila"

# 1. Inspect Database Views
# We use mysql -N (skip column names) and -e to run queries and format output as JSON-like structure or raw text to be parsed.

inspect_view() {
    local view_name=$1
    
    # Check existence
    local exists=$(mysql -u $DB_USER -p$DB_PASS -N -e "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$view_name'" 2>/dev/null || echo "0")
    
    local columns=""
    local row_count="0"
    local check_sum="0"
    
    if [ "$exists" -eq "1" ]; then
        # Get columns
        columns=$(mysql -u $DB_USER -p$DB_PASS -N -e "SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$view_name'" 2>/dev/null)
        
        # Get row count
        row_count=$(mysql -u $DB_USER -p$DB_PASS -N -e "SELECT COUNT(*) FROM $DB_NAME.$view_name" 2>/dev/null || echo "0")
        
        # Get a checksum (sum of a numeric column) to verify data isn't empty/dummy
        # Specific check depends on view. 
        if [ "$view_name" == "v_rental_by_day_category" ]; then
             check_sum=$(mysql -u $DB_USER -p$DB_PASS -N -e "SELECT SUM(total_rentals) FROM $DB_NAME.$view_name" 2>/dev/null || echo "0")
        elif [ "$view_name" == "v_monthly_rental_trend" ]; then
             check_sum=$(mysql -u $DB_USER -p$DB_PASS -N -e "SELECT SUM(total_rentals) FROM $DB_NAME.$view_name" 2>/dev/null || echo "0")
        elif [ "$view_name" == "v_rating_revenue_matrix" ]; then
             check_sum=$(mysql -u $DB_USER -p$DB_PASS -N -e "SELECT SUM(total_revenue) FROM $DB_NAME.$view_name" 2>/dev/null || echo "0")
        fi
    fi
    
    # Output JSON fragment
    echo "\"$view_name\": { \"exists\": $exists, \"columns\": \"$columns\", \"row_count\": $row_count, \"check_sum\": \"$check_sum\" }"
}

# 2. Inspect Export Files
inspect_file() {
    local filename=$1
    local filepath="$EXPORT_DIR/$filename"
    
    local exists="false"
    local mtime="0"
    local size="0"
    local lines="0"
    local created_during_task="false"
    
    if [ -f "$filepath" ]; then
        exists="true"
        mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        lines=$(wc -l < "$filepath" 2>/dev/null || echo "0")
        
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
    fi
    
    echo "\"$filename\": { \"exists\": $exists, \"mtime\": $mtime, \"size\": $size, \"lines\": $lines, \"created_during_task\": $created_during_task }"
}

# Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$TEMP_JSON"
echo "  \"views\": {" >> "$TEMP_JSON"
inspect_view "v_rental_by_day_category" >> "$TEMP_JSON"
echo "," >> "$TEMP_JSON"
inspect_view "v_monthly_rental_trend" >> "$TEMP_JSON"
echo "," >> "$TEMP_JSON"
inspect_view "v_rating_revenue_matrix" >> "$TEMP_JSON"
echo "  }," >> "$TEMP_JSON"
echo "  \"files\": {" >> "$TEMP_JSON"
inspect_file "rental_by_day_category.csv" >> "$TEMP_JSON"
echo "," >> "$TEMP_JSON"
inspect_file "rating_revenue_matrix.csv" >> "$TEMP_JSON"
echo "  }," >> "$TEMP_JSON"
echo "  \"screenshot_path\": \"/tmp/task_final.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Save final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Move JSON to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json