#!/bin/bash
echo "=== Exporting cell_reach_optimization Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/cell_reach_optimization_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/placement_candidates.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/placement_recommendation.json"

# Take final screenshot
take_screenshot /tmp/cell_reach_optimization_end.png

# Check CSV file existence and timestamps
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_STATS='{"has_rows": false, "row_count": 0, "x_range": 0.0, "y_range": 0.0, "valid_reach_rows": 0, "candidate_ids": []}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    # Parse CSV structure with Python
    CSV_STATS=$(python3 << 'PYEOF'
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/placement_candidates.csv', 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    if not rows:
        print(json.dumps({"has_rows": False, "row_count": 0, "x_range": 0.0, "y_range": 0.0, "valid_reach_rows": 0, "candidate_ids": []}))
        sys.exit(0)
    
    headers = [h.strip().lower() for h in rows[0].keys()]
    
    def find_col(candidates):
        for c in candidates:
            for h in headers:
                if c in h: return h
        return None
        
    bx_col = find_col(['base_x', 'x'])
    by_col = find_col(['base_y', 'y'])
    rc_col = find_col(['reachable_count', 'count', 'reachable'])
    dist_col = find_col(['avg_min_distance', 'distance', 'dist', 'avg'])
    cid_col = find_col(['candidate_id', 'id', 'candidate'])
    
    bx_vals, by_vals = [], []
    valid_reach_rows = 0
    candidate_ids = []
    
    for r in rows:
        try:
            if bx_col and r.get(bx_col, '').strip(): bx_vals.append(float(r[bx_col]))
            if by_col and r.get(by_col, '').strip(): by_vals.append(float(r[by_col]))
            if cid_col: candidate_ids.append(str(r.get(cid_col, '')).strip())
            
            valid_rc = False
            valid_dist = False
            
            if rc_col and r.get(rc_col, '').strip():
                rc = int(float(r[rc_col]))
                if 0 <= rc <= 6: valid_rc = True
                
            if dist_col and r.get(dist_col, '').strip():
                dist = float(r[dist_col])
                if dist >= 0: valid_dist = True
                
            if valid_rc and valid_dist:
                valid_reach_rows += 1
        except Exception:
            pass
            
    x_range = max(bx_vals) - min(bx_vals) if bx_vals else 0.0
    y_range = max(by_vals) - min(by_vals) if by_vals else 0.0
    
    print(json.dumps({
        "has_rows": True, 
        "row_count": len(rows), 
        "x_range": x_range, 
        "y_range": y_range, 
        "valid_reach_rows": valid_reach_rows,
        "candidate_ids": candidate_ids
    }))
except Exception as e:
    print(json.dumps({"error": str(e), "has_rows": False, "row_count": 0, "x_range": 0.0, "y_range": 0.0, "valid_reach_rows": 0, "candidate_ids": []}))
PYEOF
    )
fi

# Check JSON file
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_STATS='{"has_keys": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_STATS=$(python3 << 'PYEOF'
import json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/placement_recommendation.json', 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    req_keys = [
        'total_candidates', 'best_candidate_id', 'best_reachable_count', 
        'best_base_x', 'best_base_y', 'best_base_z', 
        'worst_candidate_id', 'worst_reachable_count', 'target_points_evaluated'
    ]
    has_keys = all(k in data for k in req_keys)
    
    print(json.dumps({
        "has_keys": has_keys,
        "total_candidates": int(data.get('total_candidates', 0)),
        "target_points_evaluated": int(data.get('target_points_evaluated', 0)),
        "best_candidate_id": str(data.get('best_candidate_id', '')),
        "best_reachable_count": int(data.get('best_reachable_count', -1)),
        "worst_reachable_count": int(data.get('worst_reachable_count', 999))
    }))
except Exception as e:
    print(json.dumps({"has_keys": False, "error": str(e)}))
PYEOF
    )
fi

# Combine all into a final result JSON file
cat > /tmp/cell_reach_optimization_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_stats": $CSV_STATS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_stats": $JSON_STATS
}
EOF

chmod 666 /tmp/cell_reach_optimization_result.json
echo "=== Export Complete ==="