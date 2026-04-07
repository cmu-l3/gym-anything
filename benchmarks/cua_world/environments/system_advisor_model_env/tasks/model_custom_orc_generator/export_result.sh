#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

JSON_FILE="/home/ga/Documents/SAM_Projects/orc_recovery_results.json"
JSON_EXISTS="false"
JSON_MODIFIED="false"
ANNUAL_ENERGY=0
CAPACITY_FACTOR=0
LCOE=0

# Check JSON file existence and timestamps
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
    
    # Parse values using jq
    if command -v jq &> /dev/null; then
        # Handle cases where agent might output string or number
        ANNUAL_ENERGY=$(jq -r '.annual_energy_kwh // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        CAPACITY_FACTOR=$(jq -r '.capacity_factor_percent // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        LCOE=$(jq -r '.lcoe_cents_per_kwh // 0' "$JSON_FILE" 2>/dev/null || echo "0")
    fi
fi

# Check for evidence files (PySAM script or SAM project file)
EVIDENCE_FOUND="false"
EVIDENCE_MODIFIED="false"
IS_VALID_EVIDENCE="false"

# Check Python scripts in project directory
for f in /home/ga/Documents/SAM_Projects/orc_*.py; do
    if [ -f "$f" ]; then
        EVIDENCE_FOUND="true"
        MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            EVIDENCE_MODIFIED="true"
        fi
        if grep -qi "PySAM" "$f"; then
            IS_VALID_EVIDENCE="true"
        fi
    fi
done

# Check SAM project files in project directory
for f in /home/ga/Documents/SAM_Projects/orc_*.sam; do
    if [ -f "$f" ]; then
        EVIDENCE_FOUND="true"
        MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            EVIDENCE_MODIFIED="true"
        fi
        # Basic check to ensure it's not a dummy file
        if grep -qia "system_capacity" "$f" 2>/dev/null || grep -qia "GenericSystem" "$f" 2>/dev/null || head -c 100 "$f" | grep -qi "SQLite\|JSON"; then
            IS_VALID_EVIDENCE="true"
        fi
    fi
done

# Fallback: Check if PySAM or SAM was used directly in interactive Python / Bash history
if [ "$IS_VALID_EVIDENCE" = "false" ] && [ -f /home/ga/.bash_history ]; then
    if grep -q "python" /home/ga/.bash_history; then
        # Give benefit of doubt if interactive Python was used, VLM will double check
        IS_VALID_EVIDENCE="true" 
    fi
fi

# Export all checks to a JSON summary file for the verifier
jq -n \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --arg annual_energy "$ANNUAL_ENERGY" \
    --arg capacity_factor "$CAPACITY_FACTOR" \
    --arg lcoe "$LCOE" \
    --argjson evidence_found "$EVIDENCE_FOUND" \
    --argjson evidence_modified "$EVIDENCE_MODIFIED" \
    --argjson is_valid_evidence "$IS_VALID_EVIDENCE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        json_exists: $json_exists,
        json_modified: $json_modified,
        annual_energy: $annual_energy,
        capacity_factor: $capacity_factor,
        lcoe: $lcoe,
        evidence_found: $evidence_found,
        evidence_modified: $evidence_modified,
        is_valid_evidence: $is_valid_evidence,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="