#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

EXPECTED_FILE="/home/ga/Documents/SAM_Projects/hybrid_complementarity.json"

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check for evidence file (Python script or SAM file)
EVIDENCE_EXISTS="false"
if [ -f "/home/ga/Documents/SAM_Projects/hybrid_analysis.py" ] || [ -f "/home/ga/Documents/SAM_Projects/hybrid_analysis.sam" ]; then
    EVIDENCE_EXISTS="true"
fi

# Extract JSON values
pv_annual_energy_kwh="0"
wind_annual_energy_kwh="0"
mean_50mw_pv_kw="0"
mean_50mw_wind_kw="0"
mean_100mw_hybrid_kw="0"
cv_100mw_pv="0"
cv_100mw_wind="0"
cv_100mw_hybrid="0"
VALID_STRUCTURE="false"

if [ "$FILE_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        pv_annual_energy_kwh=$(jq -r '.pv_annual_energy_kwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        wind_annual_energy_kwh=$(jq -r '.wind_annual_energy_kwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        mean_50mw_pv_kw=$(jq -r '.mean_50mw_pv_kw // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        mean_50mw_wind_kw=$(jq -r '.mean_50mw_wind_kw // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        mean_100mw_hybrid_kw=$(jq -r '.mean_100mw_hybrid_kw // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        cv_100mw_pv=$(jq -r '.cv_100mw_pv // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        cv_100mw_wind=$(jq -r '.cv_100mw_wind // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        cv_100mw_hybrid=$(jq -r '.cv_100mw_hybrid // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        
        # Check if all 8 keys exist and aren't null
        MISSING_KEYS=$(jq -r 'has("pv_annual_energy_kwh") and has("wind_annual_energy_kwh") and has("mean_50mw_pv_kw") and has("mean_50mw_wind_kw") and has("mean_100mw_hybrid_kw") and has("cv_100mw_pv") and has("cv_100mw_wind") and has("cv_100mw_hybrid")' "$EXPECTED_FILE" 2>/dev/null || echo "false")
        if [ "$MISSING_KEYS" = "true" ]; then
            VALID_STRUCTURE="true"
        fi
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson evidence_exists "$EVIDENCE_EXISTS" \
    --argjson valid_structure "$VALID_STRUCTURE" \
    --arg pv_annual "$pv_annual_energy_kwh" \
    --arg wind_annual "$wind_annual_energy_kwh" \
    --arg mean_pv "$mean_50mw_pv_kw" \
    --arg mean_wind "$mean_50mw_wind_kw" \
    --arg mean_hybrid "$mean_100mw_hybrid_kw" \
    --arg cv_pv "$cv_100mw_pv" \
    --arg cv_wind "$cv_100mw_wind" \
    --arg cv_hybrid "$cv_100mw_hybrid" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        evidence_exists: $evidence_exists,
        valid_structure: $valid_structure,
        pv_annual_energy_kwh: $pv_annual,
        wind_annual_energy_kwh: $wind_annual,
        mean_50mw_pv_kw: $mean_pv,
        mean_50mw_wind_kw: $mean_wind,
        mean_100mw_hybrid_kw: $mean_hybrid,
        cv_100mw_pv: $cv_pv,
        cv_100mw_wind: $cv_wind,
        cv_100mw_hybrid: $cv_hybrid,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="