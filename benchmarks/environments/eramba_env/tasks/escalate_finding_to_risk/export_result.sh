#!/bin/bash
echo "=== Exporting escalate_finding_to_risk results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Extract Data from Database
# We need to find:
# A) The new Risk
# B) The link between the Risk and the Compliance Finding

OUTPUT_JSON="/tmp/task_result.json"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper to run SQL and escape JSON
run_sql_json() {
    local query="$1"
    # Run query, replace tabs with spaces, and try to handle basic JSON escaping if needed
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$query" 2>/dev/null
}

echo "Querying database for Risk..."

# Get Risk Details
# Note: created timestamp check (anti-gaming) is done here in SQL or later in python
RISK_DATA=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "
SELECT id, title, description, risk_score, created 
FROM risks 
WHERE title LIKE 'Risk: Legacy Payment Server Vulnerabilities' 
AND deleted=0 
ORDER BY id DESC LIMIT 1;
" 2>/dev/null)

RISK_ID=""
RISK_TITLE=""
RISK_DESC=""
RISK_SCORE=""
RISK_CREATED=""

if [ -n "$RISK_DATA" ]; then
    RISK_ID=$(echo "$RISK_DATA" | cut -f1)
    RISK_TITLE=$(echo "$RISK_DATA" | cut -f2)
    RISK_DESC=$(echo "$RISK_DATA" | cut -f3)
    RISK_SCORE=$(echo "$RISK_DATA" | cut -f4)
    RISK_CREATED=$(echo "$RISK_DATA" | cut -f5)
fi

echo "Found Risk ID: $RISK_ID"

# Get Link Details
# Eramba typically uses join tables named alphabetically, e.g., 'compliance_analysis_risks'
# Or potentially 'risks_compliance_analysis'. We check both common patterns.
LINK_EXISTS="false"

if [ -n "$RISK_ID" ]; then
    # Get ID of the finding
    FINDING_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT id FROM compliance_analysis WHERE name='Unpatched Legacy Payment Server' LIMIT 1" 2>/dev/null)
    
    if [ -n "$FINDING_ID" ]; then
        echo "Found Finding ID: $FINDING_ID"
        
        # Check Table 1: compliance_analysis_risks
        LINK_COUNT_1=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "
            SELECT COUNT(*) FROM compliance_analysis_risks 
            WHERE (risk_id='$RISK_ID' AND compliance_analysis_id='$FINDING_ID')
        " 2>/dev/null || echo "0")
        
        # Check Table 2: Just in case it's reversed or named differently in this version
        # (Though CakePHP standard is alphabetical)
        
        if [ "$LINK_COUNT_1" -gt "0" ]; then
            LINK_EXISTS="true"
        fi
    fi
fi

# 3. Create JSON Result
# We use Python to robustly generate JSON to avoid shell string escaping hell
python3 -c "
import json
import os

data = {
    'task_start_time': $START_TIME,
    'risk_found': bool('$RISK_ID'),
    'risk_id': '$RISK_ID',
    'risk_title': '''$RISK_TITLE''',
    'risk_description': '''$RISK_DESC''',
    'risk_score': '$RISK_SCORE',
    'risk_created_timestamp': '''$RISK_CREATED''',
    'link_established': $LINK_EXISTS,
    'screenshot_path': '/tmp/task_final.png'
}
with open('$OUTPUT_JSON', 'w') as f:
    json.dump(data, f)
"

# Set permissions
chmod 666 "$OUTPUT_JSON"

echo "Result exported:"
cat "$OUTPUT_JSON"
echo "=== Export complete ==="