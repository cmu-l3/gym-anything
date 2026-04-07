#!/bin/bash
echo "=== Exporting Spatial Analysis Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check CSV Stats ---
STATS_CSV="$OUTPUT_DIR/spatial_stats.csv"
STATS_EXISTS="false"
STATS_VALID="false"
CE_INDEX="0"
CE_PVAL="1"
QUAD_PVAL="1"

if [ -f "$STATS_CSV" ] && file_modified_after "$STATS_CSV" "$TASK_START"; then
    STATS_EXISTS="true"
    
    # Parse CSV using python for robustness
    PARSED_STATS=$(python3 << PYEOF
import csv, sys
try:
    stats = {}
    with open("$STATS_CSV", 'r') as f:
        reader = csv.DictReader(f)
        # Normalize headers
        headers = [h.lower().strip() for h in reader.fieldnames]
        if 'metric' in headers and 'value' in headers:
            for row in reader:
                m = row.get('metric', '').lower().strip()
                v = row.get('value', '').strip()
                if m and v:
                    try:
                        stats[m] = float(v)
                    except:
                        pass
    
    # Extract specific keys using flexible matching
    ce_idx = 0
    ce_p = 1
    q_p = 1
    
    for k, v in stats.items():
        if 'clark' in k and 'index' in k: ce_idx = v
        if 'clark' in k and 'p' in k: ce_p = v
        if 'quadrat' in k and 'p' in k: q_p = v
        
    print(f"{ce_idx}|{ce_p}|{q_p}")
except Exception as e:
    print("0|1|1")
PYEOF
)
    CE_INDEX=$(echo "$PARSED_STATS" | cut -d'|' -f1)
    CE_PVAL=$(echo "$PARSED_STATS" | cut -d'|' -f2)
    QUAD_PVAL=$(echo "$PARSED_STATS" | cut -d'|' -f3)
fi

# --- Check Plots ---
L_PLOT="$OUTPUT_DIR/L_function_envelope.png"
L_PLOT_EXISTS="false"
L_PLOT_SIZE="0"

if [ -f "$L_PLOT" ] && file_modified_after "$L_PLOT" "$TASK_START"; then
    L_PLOT_EXISTS="true"
    L_PLOT_SIZE=$(stat -c %s "$L_PLOT")
fi

D_MAP="$OUTPUT_DIR/density_map.png"
D_MAP_EXISTS="false"
D_MAP_SIZE="0"

if [ -f "$D_MAP" ] && file_modified_after "$D_MAP" "$TASK_START"; then
    D_MAP_EXISTS="true"
    D_MAP_SIZE=$(stat -c %s "$D_MAP")
fi

# --- Check R Script ---
SCRIPT_PATH="/home/ga/RProjects/spatial_analysis.R"
SCRIPT_MODIFIED="false"
SCRIPT_HAS_SPATSTAT="false"
SCRIPT_HAS_ENVELOPE="false"

if [ -f "$SCRIPT_PATH" ] && file_modified_after "$SCRIPT_PATH" "$TASK_START"; then
    SCRIPT_MODIFIED="true"
    CONTENT=$(cat "$SCRIPT_PATH")
    if echo "$CONTENT" | grep -qi "library.*spatstat"; then
        SCRIPT_HAS_SPATSTAT="true"
    fi
    if echo "$CONTENT" | grep -qi "envelope"; then
        SCRIPT_HAS_ENVELOPE="true"
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "stats_csv_exists": $STATS_EXISTS,
    "ce_index": $CE_INDEX,
    "ce_pvalue": $CE_PVAL,
    "quadrat_pvalue": $QUAD_PVAL,
    "l_plot_exists": $L_PLOT_EXISTS,
    "l_plot_size": $L_PLOT_SIZE,
    "density_map_exists": $D_MAP_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "script_has_spatstat": $SCRIPT_HAS_SPATSTAT,
    "script_has_envelope": $SCRIPT_HAS_ENVELOPE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json