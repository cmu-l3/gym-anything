#!/bin/bash
echo "=== Exporting Tobacco Synthetic Control Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# Paths
WEIGHTS_CSV="/home/ga/RProjects/output/synthetic_weights.csv"
EFFECT_TXT="/home/ga/RProjects/output/effect_2000.txt"
PLOT_PNG="/home/ga/RProjects/output/california_path_plot.png"
SCRIPT_R="/home/ga/RProjects/tobacco_analysis.R"

# --- Check Weights CSV ---
WEIGHTS_EXISTS=false
WEIGHTS_IS_NEW=false
WEIGHTS_CONTENT=""

if [ -f "$WEIGHTS_CSV" ]; then
    WEIGHTS_EXISTS=true
    MTIME=$(stat -c %Y "$WEIGHTS_CSV" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        WEIGHTS_IS_NEW=true
    fi
    # Read content for verifier (limit size)
    WEIGHTS_CONTENT=$(cat "$WEIGHTS_CSV" | head -n 50)
fi

# --- Check Effect TXT ---
EFFECT_EXISTS=false
EFFECT_IS_NEW=false
EFFECT_VALUE="null"

if [ -f "$EFFECT_TXT" ]; then
    EFFECT_EXISTS=true
    MTIME=$(stat -c %Y "$EFFECT_TXT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        EFFECT_IS_NEW=true
    fi
    # Extract numeric value
    VAL=$(cat "$EFFECT_TXT" | grep -oE "[-+]?[0-9]*\.?[0-9]+")
    if [ -n "$VAL" ]; then
        EFFECT_VALUE="$VAL"
    fi
fi

# --- Check Plot ---
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE_BYTES=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_IS_NEW=true
    fi
    PLOT_SIZE_BYTES=$(stat -c %s "$PLOT_PNG" 2>/dev/null || echo "0")
fi

# --- Check R Script content ---
SCRIPT_HAS_SYNTH=false
SCRIPT_HAS_GGPLOT=false
if [ -f "$SCRIPT_R" ]; then
    if grep -qi "Synth" "$SCRIPT_R"; then SCRIPT_HAS_SYNTH=true; fi
    if grep -qi "ggplot" "$SCRIPT_R"; then SCRIPT_HAS_GGPLOT=true; fi
fi

# Create JSON result
# Using python to write JSON safely to avoid quoting issues
python3 -c "
import json
import os

data = {
    'weights_exists': $WEIGHTS_EXISTS,
    'weights_is_new': $WEIGHTS_IS_NEW,
    'weights_content': '''$WEIGHTS_CONTENT''',
    'effect_exists': $EFFECT_EXISTS,
    'effect_is_new': $EFFECT_IS_NEW,
    'effect_value': $EFFECT_VALUE,
    'plot_exists': $PLOT_EXISTS,
    'plot_is_new': $PLOT_IS_NEW,
    'plot_size_bytes': $PLOT_SIZE_BYTES,
    'script_has_synth': '$SCRIPT_HAS_SYNTH' == 'true',
    'script_has_ggplot': '$SCRIPT_HAS_GGPLOT' == 'true'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="