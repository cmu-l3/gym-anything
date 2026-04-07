#!/bin/bash
set -euo pipefail

echo "=== Exporting mars_orbit_capture_and_science_acquisition results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/mars_capture.script"
RESULTS_PATH="/home/ga/GMAT_output/mars_capture_results.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Function to check file existence and modification time
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during=$([ "$mtime" -ge "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check for script in alternative locations
if [ ! -f "$SCRIPT_PATH" ] && [ -f "/home/ga/Documents/missions/mars_capture.script" ]; then
    SCRIPT_PATH="/home/ga/Documents/missions/mars_capture.script"
fi

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
RESULTS_STATS=$(check_file "$RESULTS_PATH")

# Extract numerical values from results file
MOI_DV="0"
MOI_FUEL="0"
MOI_SMA="0"
MOI_ECC="0"
MOI_INC="0"
PRM_DV="0"
PRM_FUEL="0"
PRM_SMA="0"
PRM_ECC="0"
PRM_INC="0"
TOTAL_DV="0"
REMAINING_FUEL="0"
STABILITY="UNKNOWN"

if [ -f "$RESULTS_PATH" ]; then
    MOI_DV=$(grep -oP 'MOI_DeltaV_mps:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    MOI_FUEL=$(grep -oP 'MOI_Fuel_kg:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    MOI_SMA=$(grep -oP 'MOI_PostBurn_SMA_km:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    MOI_ECC=$(grep -oP 'MOI_PostBurn_ECC:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    MOI_INC=$(grep -oP 'MOI_PostBurn_INC_deg:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    PRM_DV=$(grep -oP 'PRM_DeltaV_mps:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    PRM_FUEL=$(grep -oP 'PRM_Fuel_kg:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    PRM_SMA=$(grep -oP 'PRM_PostBurn_SMA_km:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    PRM_ECC=$(grep -oP 'PRM_PostBurn_ECC:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    PRM_INC=$(grep -oP 'PRM_PostBurn_INC_deg:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    TOTAL_DV=$(grep -oP 'Total_DeltaV_mps:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    REMAINING_FUEL=$(grep -oP 'Remaining_Fuel_kg:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    STABILITY=$(grep -oP 'Stability_30day:\s*\K\S+' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "UNKNOWN")
fi

# Inspect GMAT script for required elements
MARS_CS="false"
MARS_GRAVITY="false"
SUN_PERTURBATION="false"
TANK_CONFIGURED="false"
TWO_BURNS="false"
DC_TARGETING="false"
TWO_VAR_MOI="false"

if [ -f "$SCRIPT_PATH" ]; then
    grep -qi "Origin\s*=\s*Mars" "$SCRIPT_PATH" && MARS_CS="true"
    grep -qi "Mars50c" "$SCRIPT_PATH" && MARS_GRAVITY="true"
    grep -qi "PointMasses.*Sun\|Sun.*PointMasses" "$SCRIPT_PATH" && SUN_PERTURBATION="true"
    grep -qi "Create ChemicalTank" "$SCRIPT_PATH" && TANK_CONFIGURED="true"

    # Count ImpulsiveBurn objects
    BURN_COUNT=$(grep -ci "Create ImpulsiveBurn" "$SCRIPT_PATH" 2>/dev/null || echo "0")
    [ "$BURN_COUNT" -ge 2 ] && TWO_BURNS="true"

    # Check for DC targeting
    grep -qi "Create DifferentialCorrector" "$SCRIPT_PATH" && \
    grep -qi "Target" "$SCRIPT_PATH" && \
    grep -qi "Vary" "$SCRIPT_PATH" && \
    grep -qi "Achieve" "$SCRIPT_PATH" && DC_TARGETING="true"

    # Check for 2-variable MOI (two Vary commands before first EndTarget)
    FIRST_TARGET_BLOCK=$(sed -n '/^[[:space:]]*Target/,/^[[:space:]]*EndTarget/p' "$SCRIPT_PATH" 2>/dev/null | head -50)
    if [ -n "$FIRST_TARGET_BLOCK" ]; then
        VARY_COUNT=$(echo "$FIRST_TARGET_BLOCK" | grep -ci "Vary" 2>/dev/null || echo "0")
        [ "$VARY_COUNT" -ge 2 ] && TWO_VAR_MOI="true"
    fi
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Build JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "script_path": "$SCRIPT_PATH",
    "results_path": "$RESULTS_PATH",
    "mars_coordinate_system": $MARS_CS,
    "mars_gravity_model": $MARS_GRAVITY,
    "sun_perturbation": $SUN_PERTURBATION,
    "tank_configured": $TANK_CONFIGURED,
    "two_burns_defined": $TWO_BURNS,
    "dc_targeting": $DC_TARGETING,
    "two_variable_moi": $TWO_VAR_MOI,
    "moi_deltav_mps": "$MOI_DV",
    "moi_fuel_kg": "$MOI_FUEL",
    "moi_postburn_sma_km": "$MOI_SMA",
    "moi_postburn_ecc": "$MOI_ECC",
    "moi_postburn_inc_deg": "$MOI_INC",
    "prm_deltav_mps": "$PRM_DV",
    "prm_fuel_kg": "$PRM_FUEL",
    "prm_postburn_sma_km": "$PRM_SMA",
    "prm_postburn_ecc": "$PRM_ECC",
    "prm_postburn_inc_deg": "$PRM_INC",
    "total_deltav_mps": "$TOTAL_DV",
    "remaining_fuel_kg": "$REMAINING_FUEL",
    "stability_30day": "$STABILITY"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="
