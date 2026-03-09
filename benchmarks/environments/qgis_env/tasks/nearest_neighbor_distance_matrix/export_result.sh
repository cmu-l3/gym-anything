#!/bin/bash
echo "=== Exporting nearest_neighbor_distance_matrix result ==="

source /workspace/scripts/task_utils.sh

# File paths
EXPORT_DIR="/home/ga/GIS_Data/exports"
PROJECT_DIR="/home/ga/GIS_Data/projects"
RESULT_CSV="$EXPORT_DIR/capital_distance_matrix.csv"
RESULT_QGZ="$PROJECT_DIR/distance_analysis.qgz"
RESULT_QGS="$PROJECT_DIR/distance_analysis.qgs"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CSV_MTIME=0
if [ -f "$RESULT_CSV" ]; then
    CSV_MTIME=$(stat -c %Y "$RESULT_CSV" 2>/dev/null || echo "0")
fi
FILE_NEW=$([ "$CSV_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false")

# Check if project exists
PROJECT_EXISTS="false"
if [ -f "$RESULT_QGZ" ] || [ -f "$RESULT_QGS" ]; then
    PROJECT_EXISTS="true"
fi

# Python Analysis of CSV
# We use Python to parse because the formatting can vary (headers, quotes, etc.)
ANALYSIS=$(python3 << 'PYEOF'
import csv
import json
import os
import math

csv_path = "/home/ga/GIS_Data/exports/capital_distance_matrix.csv"
result = {
    "exists": False,
    "valid_csv": False,
    "row_count": 0,
    "has_3_cols": False,
    "all_distances_positive": False,
    "distances_plausible": False,
    "correct_pairs_count": 0,
    "pairs_found": [],
    "headers": []
}

if os.path.exists(csv_path):
    result["exists"] = True
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            # Sniff dialect to handle different CSV formats
            sample = f.read(1024)
            f.seek(0)
            has_header = csv.Sniffer().has_header(sample)
            dialect = csv.Sniffer().sniff(sample)
            
            reader = csv.reader(f, dialect)
            rows = list(reader)
            
            if has_header and len(rows) > 0:
                result["headers"] = rows[0]
                data_rows = rows[1:]
            else:
                data_rows = rows

            result["row_count"] = len(data_rows)
            
            if len(data_rows) > 0:
                # Check column count (expecting at least 3: ID1, ID2, Dist)
                if len(data_rows[0]) >= 3:
                    result["has_3_cols"] = True
                
                # Analyze values
                positive_count = 0
                plausible_count = 0
                
                # Ground truth map (Bidirectional check)
                # Denver <-> Cheyenne
                # Bismarck <-> Pierre
                # Lincoln <-> Topeka
                gt_pairs = [
                    {"cities": ["Denver", "Cheyenne"], "found": False},
                    {"cities": ["Bismarck", "Pierre"], "found": False},
                    {"cities": ["Lincoln", "Topeka"], "found": False}
                ]
                
                for row in data_rows:
                    # Try to identify columns. Usually 1st=InputID, 2nd=TargetID, 3rd=Dist
                    # But if header exists, we might be smarter. 
                    # We'll assume the last numeric column is distance, or 3rd column.
                    
                    try:
                        # Extract text and numbers
                        # Normalize text for pair checking
                        row_text = [str(c).lower() for c in row]
                        
                        # Find distance (try last column first)
                        dist = float(row[-1])
                        
                        if dist > 0.0001: # Tolerance for 0
                            positive_count += 1
                        
                        # Plausible range for degrees in US (0.1 deg ~ 11km, 15 deg ~ 1600km)
                        if 0.1 < dist < 20:
                            plausible_count += 1
                            
                        # Check pairs
                        for pair in gt_pairs:
                            c1 = pair["cities"][0].lower()
                            c2 = pair["cities"][1].lower()
                            # Check if row contains both cities
                            if any(c1 in cell for cell in row_text) and any(c2 in cell for cell in row_text):
                                pair["found"] = True
                                
                    except (ValueError, IndexError):
                        continue

                result["all_distances_positive"] = (positive_count == len(data_rows) and positive_count > 0)
                result["distances_plausible"] = (plausible_count >= len(data_rows) * 0.8 and plausible_count > 0)
                
                found_pairs = [p["cities"] for p in gt_pairs if p["found"]]
                result["correct_pairs_count"] = len(found_pairs)
                result["pairs_found"] = found_pairs
                result["valid_csv"] = True

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Export to JSON
cat > /tmp/task_result.json << EOF
{
    "file_newly_created": $FILE_NEW,
    "project_saved": $PROJECT_EXISTS,
    "analysis": $ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="