#!/bin/bash
echo "=== Exporting target_visit_sequencing Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/target_visit_sequencing_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/visit_sequences.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/sequencing_report.json"

# Take final screenshot
take_screenshot /tmp/target_visit_sequencing_end_screenshot.png

# Check CSV properties
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_DATA='{"has_columns": false, "num_rows": 0, "times_valid": false, "distances_valid": false, "times_variance": 0.0, "min_time_seq_id": "", "min_time": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_DATA=$(python3 << 'PYEOF'
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/visit_sequences.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    if not rows:
        print(json.dumps({"has_columns": False, "num_rows": 0, "times_valid": False, "distances_valid": False, "times_variance": 0.0, "min_time_seq_id": "", "min_time": 0.0}))
        sys.exit(0)
    
    headers = [h.strip().lower() for h in rows[0].keys()]
    expected_cols = ['sequence_id', 'visit_order', 'total_time_s', 'total_distance_m']
    has_cols = all(c in headers for c in expected_cols)
    
    times = []
    dists = []
    min_time = float('inf')
    min_time_seq_id = ""
    
    for r in rows:
        try:
            # allow flexible case matching
            row_lower = {k.strip().lower(): v for k, v in r.items() if k}
            t = float(row_lower.get('total_time_s', 0))
            d = float(row_lower.get('total_distance_m', 0))
            sid = str(row_lower.get('sequence_id', ''))
            
            if t > 0: times.append(t)
            if d > 0: dists.append(d)
            
            if t > 0 and t < min_time:
                min_time = t
                min_time_seq_id = sid
        except Exception:
            pass
            
    times_valid = (len(times) == len(rows)) and (len(times) > 0)
    dists_valid = (len(dists) == len(rows)) and (len(dists) > 0)
    variance = (max(times) - min(times)) if times else 0.0
    
    print(json.dumps({
        "has_columns": has_cols,
        "num_rows": len(rows),
        "times_valid": times_valid,
        "distances_valid": dists_valid,
        "times_variance": variance,
        "min_time_seq_id": min_time_seq_id,
        "min_time": min_time if min_time != float('inf') else 0.0
    }))
except Exception as e:
    print(json.dumps({"has_columns": False, "num_rows": 0, "error": str(e)}))
PYEOF
    )
fi

# Check JSON properties
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_DATA='{"has_fields": false, "num_targets": 0, "num_sequences": 0, "valid_targets": false, "max_pairwise_dist": 0.0, "min_pairwise_dist": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_DATA=$(python3 << 'PYEOF'
import json, sys, math

def dist(p1, p2):
    return math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/sequencing_report.json') as f:
        d = json.load(f)
        
    req_fields = ['num_targets', 'num_sequences_tested', 'best_sequence_id', 'best_time_s', 'worst_time_s', 'improvement_pct', 'target_positions']
    has_fields = all(k in d for k in req_fields)
    
    num_targets = int(d.get('num_targets', 0))
    num_sequences = int(d.get('num_sequences_tested', 0))
    best_id = str(d.get('best_sequence_id', ''))
    best_time = float(d.get('best_time_s', 0.0))
    worst_time = float(d.get('worst_time_s', 0.0))
    imp_pct = float(d.get('improvement_pct', 0.0))
    targets = d.get('target_positions', [])
    
    valid_targets = isinstance(targets, list) and len(targets) >= 6 and all(isinstance(p, list) and len(p) == 3 for p in targets)
    
    max_pairwise = 0.0
    min_pairwise = float('inf')
    
    if valid_targets:
        for i in range(len(targets)):
            for j in range(i+1, len(targets)):
                d_ij = dist(targets[i], targets[j])
                if d_ij > max_pairwise: max_pairwise = d_ij
                if d_ij < min_pairwise: min_pairwise = d_ij
                
    if min_pairwise == float('inf'): min_pairwise = 0.0
    
    print(json.dumps({
        "has_fields": has_fields,
        "num_targets": num_targets,
        "num_sequences": num_sequences,
        "best_sequence_id": best_id,
        "best_time_s": best_time,
        "worst_time_s": worst_time,
        "improvement_pct": imp_pct,
        "valid_targets": valid_targets,
        "max_pairwise_dist": max_pairwise,
        "min_pairwise_dist": min_pairwise
    }))
except Exception as e:
    print(json.dumps({"has_fields": False, "num_targets": 0, "num_sequences": 0, "error": str(e)}))
PYEOF
    )
fi

# Write comprehensive result JSON
cat > /tmp/target_visit_sequencing_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_data": $CSV_DATA,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_data": $JSON_DATA
}
EOF

echo "=== Export Complete ==="