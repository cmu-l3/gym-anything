#!/bin/bash
echo "=== Exporting Credit Risk Explainer Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# Paths
METRICS_CSV="/home/ga/RProjects/output/model_metrics.csv"
IMP_PLOT="/home/ga/RProjects/output/variable_importance.png"
PDP_PLOT="/home/ga/RProjects/output/pdp_duration.png"
SCRIPT="/home/ga/RProjects/credit_risk_analysis.R"

# --- Metrics CSV Check ---
METRICS_EXISTS="false"
METRICS_NEW="false"
ACCURACY=0
AUC=0

if [ -f "$METRICS_CSV" ]; then
    METRICS_EXISTS="true"
    MTIME=$(stat -c %Y "$METRICS_CSV" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        METRICS_NEW="true"
    fi
    
    # Parse values using python for robustness
    VALUES=$(python3 << PYEOF
import csv
acc = 0.0
auc = 0.0
try:
    with open("$METRICS_CSV", 'r') as f:
        reader = csv.DictReader(f)
        # Handle case where headers might be different or row-based
        # Expectation: columns "metric", "value" -> row: metric="accuracy", value="0.75"
        # OR columns "accuracy", "auc" -> row: accuracy="0.75", auc="0.80"
        
        rows = list(reader)
        # Strategy 1: Tidy format (metric, value)
        for row in rows:
            m = row.get('metric', '').lower()
            v = row.get('value', 0)
            if 'acc' in m: acc = float(v)
            if 'auc' in m: auc = float(v)
            
        # Strategy 2: Wide format (accuracy, auc columns)
        if acc == 0 and auc == 0 and len(rows) > 0:
            r = rows[0]
            for k, v in r.items():
                if 'acc' in k.lower(): acc = float(v)
                if 'auc' in k.lower(): auc = float(v)
                
    print(f"{acc} {auc}")
except:
    print("0 0")
PYEOF
)
    ACCURACY=$(echo "$VALUES" | cut -d' ' -f1)
    AUC=$(echo "$VALUES" | cut -d' ' -f2)
fi

# --- Plots Check ---
check_plot() {
    local path=$1
    local exists="false"
    local new="false"
    local size=0
    
    if [ -f "$path" ]; then
        exists="true"
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            new="true"
        fi
        size=$(stat -c %s "$path" 2>/dev/null || echo "0")
    fi
    echo "$exists|$new|$size"
}

IMP_INFO=$(check_plot "$IMP_PLOT")
PDP_INFO=$(check_plot "$PDP_PLOT")

# --- Script Check ---
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
USED_PACKAGES="false"

if [ -f "$SCRIPT" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    
    # Check for keywords
    CONTENT=$(cat "$SCRIPT")
    if echo "$CONTENT" | grep -E "ranger|randomForest" > /dev/null && \
       echo "$CONTENT" | grep -E "pdp|vip|DALEX|partial" > /dev/null; then
        USED_PACKAGES="true"
    fi
fi

# Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "metrics_csv": {
        "exists": $METRICS_EXISTS,
        "is_new": $METRICS_NEW,
        "accuracy": $ACCURACY,
        "auc": $AUC
    },
    "imp_plot": {
        "exists": $(echo $IMP_INFO | cut -d'|' -f1),
        "is_new": $(echo $IMP_INFO | cut -d'|' -f2),
        "size_bytes": $(echo $IMP_INFO | cut -d'|' -f3)
    },
    "pdp_plot": {
        "exists": $(echo $PDP_INFO | cut -d'|' -f1),
        "is_new": $(echo $PDP_INFO | cut -d'|' -f2),
        "size_bytes": $(echo $PDP_INFO | cut -d'|' -f3)
    },
    "script": {
        "exists": $SCRIPT_EXISTS,
        "modified": $SCRIPT_MODIFIED,
        "used_packages": $USED_PACKAGES
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json