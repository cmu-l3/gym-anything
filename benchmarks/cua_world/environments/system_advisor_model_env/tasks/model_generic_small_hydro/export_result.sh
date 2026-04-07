#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Anti-bypass: Check if files were created during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

SCRIPT_FILE="/home/ga/Documents/SAM_Projects/small_hydro_model.py"
JSON_FILE="/home/ga/Documents/SAM_Projects/small_hydro_results.json"

SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
SCRIPT_SIZE=0
HAS_IMPORTS="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_FILE" 2>/dev/null || echo "0")
    SCRIPT_MTIME=$(stat -c%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    
    # Check for PySAM imports in the script
    if grep -q "import PySAM" "$SCRIPT_FILE" || grep -q "from PySAM" "$SCRIPT_FILE"; then
        if grep -q "GenericSystem" "$SCRIPT_FILE" && grep -q "Lcoefcr" "$SCRIPT_FILE"; then
            HAS_IMPORTS="true"
        fi
    fi
fi

JSON_EXISTS="false"
JSON_MODIFIED="false"
JSON_SIZE=0

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$JSON_FILE" 2>/dev/null || echo "0")
    JSON_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Create a high-level summary JSON for the verifier
# (The verifier will also download and deeply inspect the actual user JSON)
jq -n \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson script_modified "$SCRIPT_MODIFIED" \
    --argjson script_size "$SCRIPT_SIZE" \
    --argjson has_imports "$HAS_IMPORTS" \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson json_size "$JSON_SIZE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        script_exists: $script_exists,
        script_modified: $script_modified,
        script_size: $script_size,
        has_imports: $has_imports,
        json_exists: $json_exists,
        json_modified: $json_modified,
        json_size: $json_size,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="