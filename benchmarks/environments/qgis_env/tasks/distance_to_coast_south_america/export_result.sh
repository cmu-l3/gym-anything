#!/bin/bash
echo "=== Exporting distance_to_coast_south_america result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

EXPORT_FILE="/home/ga/GIS_Data/exports/sa_cities_coast_dist.csv"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW="false"
VALID_CSV="false"
ROW_COUNT=0
HEADERS=""
CITY_SAMPLES="{}"

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # Parse CSV with Python to validate content and extract samples
    ANALYSIS=$(python3 << 'PYEOF'
import csv
import json
import sys

csv_path = "/home/ga/GIS_Data/exports/sa_cities_coast_dist.csv"
result = {
    "valid": False,
    "headers": [],
    "row_count": 0,
    "samples": {},
    "has_name": False,
    "has_dist": False,
    "has_non_sa_cities": False
}

try:
    with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
        # Sniff delimiter
        sample = f.read(1024)
        f.seek(0)
        dialect = csv.Sniffer().sniff(sample)
        reader = csv.DictReader(f, dialect=dialect)
        
        headers = [h.strip().lower() for h in reader.fieldnames] if reader.fieldnames else []
        result["headers"] = reader.fieldnames
        
        # Check for required columns (loose matching)
        name_col = next((h for h in reader.fieldnames if "name" in h.lower()), None)
        dist_col = next((h for h in reader.fieldnames if "dist" in h.lower() or "km" in h.lower() or "hub" in h.lower()), None)
        
        if name_col: result["has_name"] = True
        if dist_col: result["has_dist"] = True
        
        rows = list(reader)
        result["row_count"] = len(rows)
        result["valid"] = True
        
        # Benchmarking specific cities
        targets = ["Lima", "Brasilia", "Brasília", "Bogota", "Bogotá", "Santiago", "La Paz", "Paris", "Tokyo"]
        
        for row in rows:
            if not name_col: break
            city_name = row[name_col]
            
            # Check for non-SA cities (Paris, Tokyo) to verify filtering
            if "Paris" in city_name or "Tokyo" in city_name:
                result["has_non_sa_cities"] = True
            
            # Extract distances for targets
            for t in targets:
                if t.lower() in city_name.lower():
                    # Normalize key
                    key = "Brasilia" if "Bras" in t else ("Bogota" if "Bog" in t else t)
                    
                    try:
                        val = float(row[dist_col])
                        result["samples"][key] = val
                    except (ValueError, TypeError):
                        pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
    )
    
    # Parse python output
    VALID_CSV=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('valid', False))")
    ROW_COUNT=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('row_count', 0))")
    HEADERS=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('headers', []))")
    CITY_SAMPLES=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('samples', {})))")
    HAS_NON_SA=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_non_sa_cities', False))")
    HAS_NAME=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_name', False))")
    HAS_DIST=$(echo "$ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_dist', False))")
fi

# Check QGIS running
IS_RUNNING="false"
if pgrep -f "qgis" > /dev/null; then
    IS_RUNNING="true"
fi

# Cleanup
if [ "$IS_RUNNING" = "true" ]; then
    kill_qgis ga 2>/dev/null || true
fi

# Construct JSON result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_new": $IS_NEW,
    "valid_csv": $VALID_CSV,
    "row_count": $ROW_COUNT,
    "headers": "$HEADERS",
    "has_name_col": $HAS_NAME,
    "has_dist_col": $HAS_DIST,
    "has_non_sa_cities": ${HAS_NON_SA:-false},
    "city_samples": $CITY_SAMPLES,
    "app_running": $IS_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="