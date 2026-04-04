#!/bin/bash
echo "=== Exporting Mitochondrial Network Analysis Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/mitochondria"

SHAPE_CSV="$RESULTS_DIR/shape_metrics.csv"
SKELETON_CSV="$RESULTS_DIR/skeleton_metrics.csv"
SKELETON_MAP="$RESULTS_DIR/skeleton_map.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to check file stats
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Parse Shape CSV using Python to extract mean Aspect Ratio
# We extract the 'AR' column or 'Aspect Ratio'
SHAPE_STATS=$(python3 -c "
import csv, sys, json
path = '$SHAPE_CSV'
stats = {'valid_rows': 0, 'mean_ar': 0.0}
try:
    with open(path, 'r') as f:
        reader = csv.DictReader(f)
        ars = []
        for row in reader:
            # Try typical column names
            val = row.get('AR') or row.get('Aspect Ratio') or row.get('AspRat')
            if val:
                try:
                    ars.append(float(val))
                except:
                    pass
        if ars:
            stats['valid_rows'] = len(ars)
            stats['mean_ar'] = sum(ars) / len(ars)
except Exception as e:
    stats['error'] = str(e)
print(json.dumps(stats))
" 2>/dev/null || echo "{\"valid_rows\": 0, \"mean_ar\": 0.0}")

# Parse Skeleton CSV to check for branches
# Usually 'Number of Branches' or '# Branches'
SKELETON_STATS=$(python3 -c "
import csv, sys, json
path = '$SKELETON_CSV'
stats = {'valid_rows': 0, 'total_branches': 0}
try:
    with open(path, 'r') as f:
        reader = csv.DictReader(f)
        branches = 0
        rows = 0
        for row in reader:
            rows += 1
            # Try finding branch column
            for k, v in row.items():
                if 'branch' in k.lower() and 'len' not in k.lower(): # avoid branch length for count
                    try:
                        branches += float(v)
                    except:
                        pass
        stats['valid_rows'] = rows
        stats['total_branches'] = branches
except Exception as e:
    stats['error'] = str(e)
print(json.dumps(stats))
" 2>/dev/null || echo "{\"valid_rows\": 0, \"total_branches\": 0}")

# Build Result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "shape_csv": $(check_file "$SHAPE_CSV"),
    "skeleton_csv": $(check_file "$SKELETON_CSV"),
    "skeleton_map": $(check_file "$SKELETON_MAP"),
    "shape_metrics": $SHAPE_STATS,
    "skeleton_metrics": $SKELETON_STATS
}
EOF

echo "Result JSON created at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="