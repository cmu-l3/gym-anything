#!/bin/bash
echo "=== Exporting Airport Network Resilience Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

# Paths
CENTRALITY_CSV="/home/ga/RProjects/output/airport_centrality.csv"
COMMUNITY_CSV="/home/ga/RProjects/output/airport_communities.csv"
RESILIENCE_CSV="/home/ga/RProjects/output/airport_resilience.csv"
NETWORK_PNG="/home/ga/RProjects/output/airport_network.png"
SCRIPT_PATH="/home/ga/RProjects/airport_network_analysis.R"

# Helper to check file status
check_file() {
    local fpath="$1"
    local exists="false"
    local is_new="false"
    local size="0"

    if [ -f "$fpath" ]; then
        exists="true"
        size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new="true"
        fi
    fi
    echo "$exists|$is_new|$size"
}

# Check all files
IFS='|' read C_EXISTS C_NEW C_SIZE <<< $(check_file "$CENTRALITY_CSV")
IFS='|' read M_EXISTS M_NEW M_SIZE <<< $(check_file "$COMMUNITY_CSV")
IFS='|' read R_EXISTS R_NEW R_SIZE <<< $(check_file "$RESILIENCE_CSV")
IFS='|' read P_EXISTS P_NEW P_SIZE <<< $(check_file "$NETWORK_PNG")
IFS='|' read S_EXISTS S_NEW S_SIZE <<< $(check_file "$SCRIPT_PATH")

# Analyze Content with Python
# We extract key metrics directly from the CSVs to make verification robust
# without needing to run R in the verification phase.
PYTHON_ANALYSIS=$(python3 << PYEOF
import csv
import json
import sys

results = {
    "atl_rank": -1,
    "top_hub": "",
    "centrality_rows": 0,
    "centrality_cols": [],
    "community_count": 0,
    "community_rows": 0,
    "resilience_rows": 0,
    "resilience_trend": "none", # decreasing, increasing, mixed
    "script_content_check": False
}

# 1. Analyze Centrality
try:
    with open("$CENTRALITY_CSV", 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        results["centrality_rows"] = len(rows)
        results["centrality_cols"] = reader.fieldnames
        
        # Check if ATL is in top rows
        for idx, row in enumerate(rows[:30]):
            code = row.get('airport', '').strip().upper()
            if code == 'ATL':
                results["atl_rank"] = idx + 1
            if idx == 0:
                results["top_hub"] = code
except Exception:
    pass

# 2. Analyze Communities
try:
    with open("$COMMUNITY_CSV", 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        results["community_rows"] = len(rows)
        communities = set(row.get('community', '') for row in rows)
        results["community_count"] = len(communities)
except Exception:
    pass

# 3. Analyze Resilience
try:
    with open("$RESILIENCE_CSV", 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        results["resilience_rows"] = len(rows)
        
        # Check trend of component size
        sizes = []
        for row in rows:
            try:
                # support various column names
                val = row.get('largest_component_size') or row.get('fraction_reachable')
                if val:
                    sizes.append(float(val))
            except:
                pass
        
        if len(sizes) > 1:
            if all(x >= y for x, y in zip(sizes, sizes[1:])):
                results["resilience_trend"] = "decreasing"
            elif all(x <= y for x, y in zip(sizes, sizes[1:])):
                results["resilience_trend"] = "increasing"
            else:
                results["resilience_trend"] = "mixed"
except Exception:
    pass

# 4. Check Script
try:
    with open("$SCRIPT_PATH", 'r') as f:
        content = f.read()
        if "igraph" in content and ("betweenness" in content or "centrality" in content):
            results["script_content_check"] = True
except Exception:
    pass

print(json.dumps(results))
PYEOF
)

# Construct final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "files": {
        "centrality": {"exists": $C_EXISTS, "new": $C_NEW, "size": $C_SIZE},
        "communities": {"exists": $M_EXISTS, "new": $M_NEW, "size": $M_SIZE},
        "resilience": {"exists": $R_EXISTS, "new": $R_NEW, "size": $R_SIZE},
        "network_plot": {"exists": $P_EXISTS, "new": $P_NEW, "size": $P_SIZE},
        "script": {"exists": $S_EXISTS, "new": $S_NEW}
    },
    "analysis": $PYTHON_ANALYSIS
}
EOF

# Save and cleanup
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="