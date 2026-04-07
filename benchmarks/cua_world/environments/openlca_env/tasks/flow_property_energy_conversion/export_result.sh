#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Flow Property Conversion Result ==="

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Check for Output File
OUTPUT_FILE="/home/ga/LCA_Results/biomass_inventory.csv"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
CALCULATED_MASS="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Extract content for verification (first 10 lines)
    OUTPUT_CONTENT=$(head -n 20 "$OUTPUT_FILE" | base64 -w 0)
    
    # Try to find the calculated mass in the CSV
    # Look for lines containing "Biomass" and extract numbers
    CALCULATED_MASS=$(grep -i "Biomass" "$OUTPUT_FILE" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0")
fi

# 3. Database Verification (The Core Check)
# We need to verify:
# A. Conversion factor exists (18.5)
# B. Process input is defined as 1000.0 (MJ), implying the unit was switched

DB_DIR="/home/ga/openLCA-data-1.4/databases"
# Find the active database (most recently modified or largest)
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

DB_CHECK_FLOW="false"
DB_CHECK_FACTOR="false"
DB_CHECK_INPUT_AMOUNT="0"
DB_CHECK_UNIT_TYPE="unknown"

if [ -n "$ACTIVE_DB" ]; then
    echo "Checking database: $ACTIVE_DB"
    
    # A. Check if Flow exists
    FLOW_QUERY="SELECT NAME FROM TBL_FLOWS WHERE NAME LIKE '%Biomass Fuel Pellets%'"
    FLOW_RES=$(derby_query "$ACTIVE_DB" "$FLOW_QUERY")
    if echo "$FLOW_RES" | grep -qi "Biomass"; then
        DB_CHECK_FLOW="true"
    fi

    # B. Check for Conversion Factor (18.5)
    # TBL_FLOW_PROPERTY_FACTORS links to flows. We look for the value.
    FACTOR_QUERY="SELECT CONVERSION_FACTOR FROM TBL_FLOW_PROPERTY_FACTORS WHERE CONVERSION_FACTOR > 18.4 AND CONVERSION_FACTOR < 18.6"
    FACTOR_RES=$(derby_query "$ACTIVE_DB" "$FACTOR_QUERY")
    if echo "$FACTOR_RES" | grep -q "18.5"; then
        DB_CHECK_FACTOR="true"
    fi

    # C. Check Process Input Amount (Crucial for "don't calculate manually" rule)
    # We look for an exchange with amount 1000.0 linked to the biomass flow
    # Note: If they entered 1000 MJ, the AMOUNT_VALUE in DB is 1000.0. 
    # If they manually calc'd 54 kg, AMOUNT_VALUE is 54.05.
    INPUT_QUERY="SELECT e.AMOUNT_VALUE FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE f.NAME LIKE '%Biomass Fuel Pellets%' AND e.IS_INPUT = 1"
    INPUT_RES=$(derby_query "$ACTIVE_DB" "$INPUT_QUERY")
    
    # Extract the number
    DB_CHECK_INPUT_AMOUNT=$(echo "$INPUT_RES" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0")
fi

# 4. Prepare Result JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "calculated_mass_from_csv": "$CALCULATED_MASS",
    "db_flow_exists": $DB_CHECK_FLOW,
    "db_factor_correct": $DB_CHECK_FACTOR,
    "db_input_amount": $DB_CHECK_INPUT_AMOUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json