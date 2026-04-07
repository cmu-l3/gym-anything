#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Stoichiometric Process Modeling results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for the text file output
TXT_OUTPUT="/home/ga/LCA_Results/stoichiometry_check.txt"
TXT_CONTENT=""
TXT_EXISTS="false"
if [ -f "$TXT_OUTPUT" ]; then
    TXT_EXISTS="true"
    TXT_CONTENT=$(cat "$TXT_OUTPUT" | head -n 5) # Read first few lines
fi

# 3. Query the Derby database for the Process and its Exchanges
# We need to find the active database first.
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""

# Heuristic: Find the most recently modified database folder
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

PROCESS_FOUND="false"
INPUT_AMOUNT=0
PRODUCT_AMOUNT=0
CO2_AMOUNT=0
PROCESS_NAME=""

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database at: $ACTIVE_DB"
    
    # Query to get the process ID and exchanges
    # Structure: 
    # TBL_PROCESSES: ID, NAME
    # TBL_EXCHANGES: F_OWNER (ref TBL_PROCESSES.ID), F_FLOW (ref TBL_FLOWS.ID), RESULT_AMOUNT, IS_INPUT
    # TBL_FLOWS: ID, NAME
    
    SQL_QUERY="
    SELECT p.NAME, f.NAME, e.RESULT_AMOUNT, e.IS_INPUT 
    FROM TBL_PROCESSES p 
    JOIN TBL_EXCHANGES e ON p.ID = e.F_OWNER 
    JOIN TBL_FLOWS f ON e.F_FLOW = f.ID 
    WHERE p.NAME = 'Quicklime Production, stoichiometric';
    "
    
    # Close OpenLCA to unlock Derby DB (crucial!)
    close_openlca
    sleep 5
    
    QUERY_RESULT=$(derby_query "$ACTIVE_DB" "$SQL_QUERY")
    
    # echo "Raw Query Result:"
    # echo "$QUERY_RESULT"
    
    # Parse the result
    if echo "$QUERY_RESULT" | grep -q "Quicklime Production, stoichiometric"; then
        PROCESS_FOUND="true"
        PROCESS_NAME="Quicklime Production, stoichiometric"
        
        # Extract values using regex or line parsing
        # Output format is typically: NAME | NAME | RESULT_AMOUNT | IS_INPUT
        
        # Find Limestone Input
        # Look for line containing 'Limestone' and '1' (IS_INPUT=1)
        INPUT_LINE=$(echo "$QUERY_RESULT" | grep -i "Limestone" | grep "1$")
        if [ -n "$INPUT_LINE" ]; then
            # Extract the number (RESULT_AMOUNT)
            # Typically col 3. Assuming standard formatting, but let's use grep -oP for floating point
            INPUT_AMOUNT=$(echo "$INPUT_LINE" | grep -oP '\d+\.\d+' | head -1 || echo "0")
            # Fallback if integer
            if [ -z "$INPUT_AMOUNT" ]; then INPUT_AMOUNT=$(echo "$INPUT_LINE" | grep -oP '\b\d+\b' | grep -v "1$" | head -1 || echo "0"); fi
        fi
        
        # Find Quicklime Output
        # Look for line containing 'Quicklime' or 'Lime' and '0' (IS_INPUT=0)
        PRODUCT_LINE=$(echo "$QUERY_RESULT" | grep -iE "Quicklime|Lime" | grep "0$" | grep -v "Carbon")
        if [ -n "$PRODUCT_LINE" ]; then
            PRODUCT_AMOUNT=$(echo "$PRODUCT_LINE" | grep -oP '\d+\.\d+' | head -1 || echo "0")
            if [ -z "$PRODUCT_AMOUNT" ]; then PRODUCT_AMOUNT=$(echo "$PRODUCT_LINE" | grep -oP '\b\d+\b' | grep -v "0$" | head -1 || echo "0"); fi
        fi
        
        # Find CO2 Emission
        # Look for line containing 'Carbon dioxide' or 'CO2' and '0' (IS_INPUT=0)
        CO2_LINE=$(echo "$QUERY_RESULT" | grep -iE "Carbon dioxide|CO2" | grep "0$")
        if [ -n "$CO2_LINE" ]; then
            CO2_AMOUNT=$(echo "$CO2_LINE" | grep -oP '\d+\.\d+' | head -1 || echo "0")
            if [ -z "$CO2_AMOUNT" ]; then CO2_AMOUNT=$(echo "$CO2_LINE" | grep -oP '\b\d+\b' | grep -v "0$" | head -1 || echo "0"); fi
        fi
    fi
else
    echo "No active database found."
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "process_found": $PROCESS_FOUND,
    "process_name": "$PROCESS_NAME",
    "input_limestone": "$INPUT_AMOUNT",
    "output_quicklime": "$PRODUCT_AMOUNT",
    "output_co2": "$CO2_AMOUNT",
    "txt_exists": $TXT_EXISTS,
    "txt_content": "$(echo "$TXT_CONTENT" | tr -d '\n' | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="