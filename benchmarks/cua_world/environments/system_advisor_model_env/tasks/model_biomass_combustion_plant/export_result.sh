#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File paths
JSON_FILE="/home/ga/Documents/SAM_Projects/biomass_results.json"
PY_FILE="/home/ga/Documents/SAM_Projects/biomass_model.py"

JSON_EXISTS="false"
JSON_MODIFIED="false"
JSON_SIZE=0

PY_EXISTS="false"
PY_MODIFIED="false"
PYSAM_IMPORTED="false"

# Check JSON output
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Check Python script
if [ -f "$PY_FILE" ]; then
    PY_EXISTS="true"
    
    FILE_MTIME=$(stat -c%Y "$PY_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PY_MODIFIED="true"
    fi
    
    # Check for PySAM imports in the script
    if grep -ql "import PySAM" "$PY_FILE" 2>/dev/null || grep -ql "from PySAM" "$PY_FILE" 2>/dev/null; then
        PYSAM_IMPORTED="true"
    fi
fi

# Check bash history for python execution
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3.*biomass" /home/ga/.bash_history 2>/dev/null || grep -q "python.*biomass" /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Extract values from JSON if it exists and is valid
NAMEPLATE_KW="0"
ANNUAL_KWH="0"
CAPACITY_FACTOR="0"

if [ "$JSON_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$JSON_FILE" 2>/dev/null; then
        NAMEPLATE_KW=$(jq -r '
            .nameplate_kw // 
            .nameplate // 
            .system_capacity_kw // 
            "0"
        ' "$JSON_FILE" 2>/dev/null || echo "0")
        
        ANNUAL_KWH=$(jq -r '
            .annual_energy_kwh // 
            .annual_energy // 
            .annual_kwh // 
            "0"
        ' "$JSON_FILE" 2>/dev/null || echo "0")
        
        CAPACITY_FACTOR=$(jq -r '
            .capacity_factor_percent // 
            .capacity_factor // 
            "0"
        ' "$JSON_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson json_size "$JSON_SIZE" \
    --argjson py_exists "$PY_EXISTS" \
    --argjson py_modified "$PY_MODIFIED" \
    --argjson pysam_imported "$PYSAM_IMPORTED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg nameplate_kw "$NAMEPLATE_KW" \
    --arg annual_kwh "$ANNUAL_KWH" \
    --arg capacity_factor "$CAPACITY_FACTOR" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        json_exists: $json_exists,
        json_modified: $json_modified,
        json_size: $json_size,
        py_exists: $py_exists,
        py_modified: $py_modified,
        pysam_imported: $pysam_imported,
        python_ran: $python_ran,
        nameplate_kw: $nameplate_kw,
        annual_kwh: $annual_kwh,
        capacity_factor: $capacity_factor,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="