#!/bin/bash
# Export script for Add Satellite Clinic task
# Extracts the created branch/clinic record from the database for verification

echo "=== Exporting Add Satellite Clinic Result ==="

source /workspace/scripts/task_utils.sh

# ==============================================================================
# 1. Capture Final State Visuals
# ==============================================================================
take_screenshot /tmp/task_final_screenshot.png

# ==============================================================================
# 2. Query Database for Result
# ==============================================================================
# We look for the specific clinic name created during the task
TARGET_NAME="West End Clinic"

# Query the 'branch' table (standard for multi-site in OSCAR)
# We fetch relevant columns to verify address/phone details
# Using fuzzy matching (LIKE) just in case, but usually strict match on name is expected
# branch schema often includes: branch_no, location, address, city, province, postal, phone, fax

echo "Querying database for '$TARGET_NAME'..."

# Get the most recent branch that matches the name
# We output as tab-separated values to parse easily
BRANCH_DATA=$(oscar_query "SELECT location, address, city, province, phone, fax, status, lastUpdateDate FROM branch WHERE location LIKE '%${TARGET_NAME}%' OR description LIKE '%${TARGET_NAME}%' ORDER BY branch_no DESC LIMIT 1" 2>/dev/null)

# Fallback: if 'location' column doesn't exist (older schemas), try 'description' or just dump *
if [ -z "$BRANCH_DATA" ]; then
    echo "  (No match found in specific query, checking generic count...)"
fi

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_branch_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM branch" || echo "0")

# ==============================================================================
# 3. Parse Data
# ==============================================================================
BRANCH_FOUND="false"
B_NAME=""
B_ADDR=""
B_CITY=""
B_PROV=""
B_PHONE=""
B_FAX=""

if [ -n "$BRANCH_DATA" ]; then
    BRANCH_FOUND="true"
    # Parse tab-separated output
    B_NAME=$(echo "$BRANCH_DATA" | cut -f1)
    B_ADDR=$(echo "$BRANCH_DATA" | cut -f2)
    B_CITY=$(echo "$BRANCH_DATA" | cut -f3)
    B_PROV=$(echo "$BRANCH_DATA" | cut -f4)
    B_PHONE=$(echo "$BRANCH_DATA" | cut -f5)
    B_FAX=$(echo "$BRANCH_DATA" | cut -f6)
    echo "Found Branch: $B_NAME, $B_ADDR, $B_PHONE"
else
    echo "No branch record found for '$TARGET_NAME'."
fi

# ==============================================================================
# 4. Generate JSON Output
# ==============================================================================
# Use temp file to avoid permission issues when creating the JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape strings for JSON safely
json_escape() {
    echo "$1" | sed 's/"/\\"/g'
}

SAFE_B_NAME=$(json_escape "$B_NAME")
SAFE_B_ADDR=$(json_escape "$B_ADDR")
SAFE_B_CITY=$(json_escape "$B_CITY")
SAFE_B_PROV=$(json_escape "$B_PROV")
SAFE_B_PHONE=$(json_escape "$B_PHONE")
SAFE_B_FAX=$(json_escape "$B_FAX")

cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $(cat /tmp/task_start_timestamp 2>/dev/null || echo "0"),
    "initial_branch_count": $INITIAL_COUNT,
    "current_branch_count": $CURRENT_COUNT,
    "branch_found": $BRANCH_FOUND,
    "branch_data": {
        "name": "$SAFE_B_NAME",
        "address": "$SAFE_B_ADDR",
        "city": "$SAFE_B_CITY",
        "province": "$SAFE_B_PROV",
        "phone": "$SAFE_B_PHONE",
        "fax": "$SAFE_B_FAX"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="