#!/bin/bash
echo "=== Exporting task result ==="

# Record task end state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SCRIPT_PATH="/home/ga/Documents/SAM_Projects/linear_fresnel_iph.py"
JSON_PATH="/home/ga/Documents/SAM_Projects/linear_fresnel_iph_results.json"

# Check Script
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
SCRIPT_SIZE=0
HAS_MODULE="false"
HAS_EXECUTE="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_PATH" 2>/dev/null || echo "0")
    
    SCRIPT_MTIME=$(stat -c%Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    
    if grep -q "LinearFresnelDsgIph" "$SCRIPT_PATH"; then
        HAS_MODULE="true"
    fi
    
    if grep -q "\.execute()" "$SCRIPT_PATH"; then
        HAS_EXECUTE="true"
    fi
fi

# Check JSON
JSON_EXISTS="false"
JSON_MODIFIED="false"
JSON_SIZE=0
ANNUAL_ENERGY="0"
CF="0"
APERTURE="0"
T_OUT="0"
T_IN="0"
PRESSURE="0"
LAT="0"
LON="0"

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$JSON_PATH" 2>/dev/null || echo "0")
    
    JSON_MTIME=$(stat -c%Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
    
    # Try parsing metrics via jq if available
    if command -v jq &> /dev/null && jq empty "$JSON_PATH" 2>/dev/null; then
        ANNUAL_ENERGY=$(jq -r '.annual_energy_kwh // .annual_energy // .annual_thermal_energy // "0"' "$JSON_PATH" 2>/dev/null)
        CF=$(jq -r '.capacity_factor_percent // .capacity_factor // .capacity_factor_pct // "0"' "$JSON_PATH" 2>/dev/null)
        APERTURE=$(jq -r '.solar_field_aperture_m2 // .aperture_area // .solar_field_area // .solar_field_aperture // "0"' "$JSON_PATH" 2>/dev/null)
        T_OUT=$(jq -r '.design_outlet_temp_c // .outlet_temp // .design_outlet_temp // "0"' "$JSON_PATH" 2>/dev/null)
        T_IN=$(jq -r '.design_inlet_temp_c // .inlet_temp // .design_inlet_temp // "0"' "$JSON_PATH" 2>/dev/null)
        PRESSURE=$(jq -r '.operating_pressure_bar // .operating_pressure // .pressure_bar // "0"' "$JSON_PATH" 2>/dev/null)
        LAT=$(jq -r '.latitude // .lat // "0"' "$JSON_PATH" 2>/dev/null)
        LON=$(jq -r '.longitude // .lon // "0"' "$JSON_PATH" 2>/dev/null)
    fi
fi

# Bundle results safely via jq to handle any bad characters
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson script_modified "$SCRIPT_MODIFIED" \
    --argjson script_size "$SCRIPT_SIZE" \
    --argjson has_module "$HAS_MODULE" \
    --argjson has_execute "$HAS_EXECUTE" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson json_size "$JSON_SIZE" \
    --arg annual_energy "$ANNUAL_ENERGY" \
    --arg cf "$CF" \
    --arg aperture "$APERTURE" \
    --arg t_out "$T_OUT" \
    --arg t_in "$T_IN" \
    --arg pressure "$PRESSURE" \
    --arg lat "$LAT" \
    --arg lon "$LON" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        script_modified: $script_modified,
        script_size: $script_size,
        has_module: $has_module,
        has_execute: $has_execute,
        json_exists: $json_exists,
        json_modified: $json_modified,
        json_size: $json_size,
        annual_energy: $annual_energy,
        cf: $cf,
        aperture: $aperture,
        t_out: $t_out,
        t_in: $t_in,
        pressure: $pressure,
        lat: $lat,
        lon: $lon,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="