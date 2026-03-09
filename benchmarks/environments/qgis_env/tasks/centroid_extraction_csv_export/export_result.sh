#!/bin/bash
echo "=== Exporting centroid_extraction_csv_export result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

take_screenshot /tmp/task_end.png

# Paths
EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/south_america_centroids.csv"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check file existence and freshness
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
ANALYSIS='{}'

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Analyze CSV content with Python
    ANALYSIS=$(python3 << 'PYEOF'
import csv
import json
import sys

csv_path = "/home/ga/GIS_Data/exports/south_america_centroids.csv"
result = {
    "valid_csv": False,
    "row_count": 0,
    "headers": [],
    "lon_range": [0, 0],
    "lat_range": [0, 0],
    "countries_found": [],
    "coords_valid": False
}

try:
    with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
        # Sniff dialect or assume standard
        try:
            sample = f.read(1024)
            f.seek(0)
            dialect = csv.Sniffer().sniff(sample)
        except csv.Error:
            dialect = 'excel'
            f.seek(0)

        reader = csv.DictReader(f, dialect=dialect)
        headers = reader.fieldnames or []
        result["headers"] = [h.lower() for h in headers]
        
        rows = list(reader)
        result["row_count"] = len(rows)
        result["valid_csv"] = True

        # Identify coordinate columns (fuzzy match)
        lon_col = next((h for h in headers if any(x in h.lower() for x in ['lon', 'x', 'x_coord'])), None)
        lat_col = next((h for h in headers if any(x in h.lower() for x in ['lat', 'y', 'y_coord'])), None)
        
        # Identify name column
        name_col = next((h for h in headers if any(x in h.lower() for x in ['name', 'admin', 'country'])), None)

        lons = []
        lats = []
        countries = []

        for row in rows:
            # Extract coordinates
            if lon_col and lat_col:
                try:
                    lx = float(row[lon_col])
                    ly = float(row[lat_col])
                    lons.append(lx)
                    lats.append(ly)
                except (ValueError, TypeError):
                    pass
            
            # Extract names
            if name_col:
                countries.append(row[name_col])
            else:
                # If no clear name col, check all values for known countries
                for v in row.values():
                    if v in ["Brazil", "Argentina", "Chile", "Colombia", "Peru"]:
                        countries.append(v)
                        break

        if lons and lats:
            result["lon_range"] = [min(lons), max(lons)]
            result["lat_range"] = [min(lats), max(lats)]
            result["coords_valid"] = True
            
        result["countries_found"] = list(set(countries))

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
    )
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPECTED_FILE",
    "file_size_bytes": $FILE_SIZE,
    "file_fresh": $FILE_CREATED_DURING_TASK,
    "analysis": $ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="