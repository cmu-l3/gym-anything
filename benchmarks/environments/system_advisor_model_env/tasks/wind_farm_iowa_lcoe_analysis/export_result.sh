#!/bin/bash
echo "=== Exporting wind_farm_iowa_lcoe_analysis result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/wind_task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Anti-bypass: check if PySAM Windpower was actually used
PYTHON_RAN="false"
WIND_MODEL_USED="false"

PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "Windpower\|windpower\|wind_turbine\|wind_farm\|PySAM.Wind" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            WIND_MODEL_USED="true"
            break
        fi
        if grep -ql "import PySAM\|from PySAM" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
        fi
    done
fi

# Also check bash history
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check result file
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/Iowa_Wind_LCOE_Analysis.json"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"
NUM_CONFIGS="0"
MIN_LCOE="0"
MAX_CF="0"
OPTIMAL_CONFIG=""
HAS_CONFIGS="false"
FIRST_AEP="0"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi

    if command -v jq &> /dev/null && jq empty "$EXPECTED_FILE" 2>/dev/null; then
        # Count configurations
        NUM_CONFIGS=$(jq -r '
            (.configurations // .configs // .results // []) | length
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        if [ "$NUM_CONFIGS" -gt "0" ]; then
            HAS_CONFIGS="true"
        fi

        # Extract minimum LCOE across configurations
        MIN_LCOE=$(jq -r '
            [
                (.configurations // .configs // .results // [])[] |
                (.lcoe_usd_per_mwh // .lcoe // .LCOE // .lcoe_real // 0) |
                select(. > 0)
            ] | if length > 0 then min else 0 end
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        # Extract max capacity factor
        MAX_CF=$(jq -r '
            [
                (.configurations // .configs // .results // [])[] |
                (.capacity_factor_pct // .capacity_factor // .cf // .CF // 0) |
                select(. > 0)
            ] | if length > 0 then max else 0 end
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        # Extract first AEP for plausibility check
        FIRST_AEP=$(jq -r '
            (.configurations // .configs // .results // []) |
            if length > 0 then .[0] |
                (.annual_energy_mwh // .aep_mwh // .annual_energy // .aep // 0)
            else 0 end
        ' "$EXPECTED_FILE" 2>/dev/null || echo "0")

        # Extract optimal configuration name
        OPTIMAL_CONFIG=$(jq -r '
            .optimal_configuration //
            .best_configuration //
            .recommended_configuration //
            .optimal //
            ""
        ' "$EXPECTED_FILE" 2>/dev/null || echo "")
    fi
fi

# Write result JSON using jq for safety
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_size "$FILE_SIZE" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson wind_model_used "$WIND_MODEL_USED" \
    --arg num_configs "$NUM_CONFIGS" \
    --argjson has_configs "$HAS_CONFIGS" \
    --arg min_lcoe "$MIN_LCOE" \
    --arg max_cf "$MAX_CF" \
    --arg first_aep "$FIRST_AEP" \
    --arg optimal_config "$OPTIMAL_CONFIG" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_size: $file_size,
        file_modified: $file_modified,
        python_ran: $python_ran,
        wind_model_used: $wind_model_used,
        num_configs: $num_configs,
        has_configs: $has_configs,
        min_lcoe: $min_lcoe,
        max_cf: $max_cf,
        first_aep: $first_aep,
        optimal_config: $optimal_config,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
