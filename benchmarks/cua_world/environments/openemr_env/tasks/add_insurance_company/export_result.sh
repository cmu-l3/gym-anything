#!/bin/bash
# Export script for Add Insurance Company task

echo "=== Exporting Add Insurance Company Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial counts and IDs
INITIAL_COUNT=$(cat /tmp/initial_insurance_count.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_insurance_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get current insurance company count
CURRENT_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM insurance_companies" 2>/dev/null || echo "0")

echo "Insurance company count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Search for the target insurance company using multiple patterns (case-insensitive)
echo ""
echo "=== Searching for Blue Cross Blue Shield of Massachusetts ==="

# Primary search: exact company name pattern
COMPANY_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, name, attn, address, city, state, zip, phone, cms_id 
     FROM insurance_companies 
     WHERE LOWER(name) LIKE '%blue cross%' AND LOWER(name) LIKE '%massachusetts%'
     ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Secondary search: BCBS MA pattern
if [ -z "$COMPANY_DATA" ]; then
    echo "Primary search failed, trying BCBS pattern..."
    COMPANY_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT id, name, attn, address, city, state, zip, phone, cms_id 
         FROM insurance_companies 
         WHERE (LOWER(name) LIKE '%bcbs%' AND LOWER(name) LIKE '%ma%')
            OR (LOWER(name) LIKE '%bcbs%' AND LOWER(name) LIKE '%massachusetts%')
         ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Tertiary search: any new insurance company with Boston
if [ -z "$COMPANY_DATA" ]; then
    echo "Secondary search failed, checking for any new Boston insurance company..."
    COMPANY_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT id, name, attn, address, city, state, zip, phone, cms_id 
         FROM insurance_companies 
         WHERE id > $INITIAL_MAX_ID AND LOWER(city) = 'boston'
         ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Final fallback: any new insurance company
if [ -z "$COMPANY_DATA" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    echo "City search failed, checking for any new insurance company..."
    COMPANY_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT id, name, attn, address, city, state, zip, phone, cms_id 
         FROM insurance_companies 
         WHERE id > $INITIAL_MAX_ID
         ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

# Parse company data
COMPANY_FOUND="false"
COMPANY_ID=""
COMPANY_NAME=""
COMPANY_ATTN=""
COMPANY_ADDRESS=""
COMPANY_CITY=""
COMPANY_STATE=""
COMPANY_ZIP=""
COMPANY_PHONE=""
COMPANY_CMS_ID=""
NEWLY_CREATED="false"

if [ -n "$COMPANY_DATA" ]; then
    COMPANY_FOUND="true"
    # Parse tab-separated values
    COMPANY_ID=$(echo "$COMPANY_DATA" | cut -f1)
    COMPANY_NAME=$(echo "$COMPANY_DATA" | cut -f2)
    COMPANY_ATTN=$(echo "$COMPANY_DATA" | cut -f3)
    COMPANY_ADDRESS=$(echo "$COMPANY_DATA" | cut -f4)
    COMPANY_CITY=$(echo "$COMPANY_DATA" | cut -f5)
    COMPANY_STATE=$(echo "$COMPANY_DATA" | cut -f6)
    COMPANY_ZIP=$(echo "$COMPANY_DATA" | cut -f7)
    COMPANY_PHONE=$(echo "$COMPANY_DATA" | cut -f8)
    COMPANY_CMS_ID=$(echo "$COMPANY_DATA" | cut -f9)
    
    # Check if this is a newly created entry
    if [ -n "$COMPANY_ID" ] && [ "$COMPANY_ID" -gt "$INITIAL_MAX_ID" ]; then
        NEWLY_CREATED="true"
    fi
    
    echo ""
    echo "Insurance company found:"
    echo "  ID: $COMPANY_ID"
    echo "  Name: $COMPANY_NAME"
    echo "  Address: $COMPANY_ADDRESS"
    echo "  City: $COMPANY_CITY"
    echo "  State: $COMPANY_STATE"
    echo "  ZIP: $COMPANY_ZIP"
    echo "  Phone: $COMPANY_PHONE"
    echo "  CMS ID: $COMPANY_CMS_ID"
    echo "  Newly Created: $NEWLY_CREATED"
else
    echo "Insurance company NOT found in database"
fi

# Debug: Show recent insurance companies
echo ""
echo "=== DEBUG: Most recent insurance companies ==="
docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
    "SELECT id, name, city, state, zip FROM insurance_companies ORDER BY id DESC LIMIT 5" 2>/dev/null || true
echo "=== END DEBUG ==="

# Escape special characters for JSON
COMPANY_NAME_ESCAPED=$(echo "$COMPANY_NAME" | sed 's/"/\\"/g' | tr '\n' ' ')
COMPANY_ADDRESS_ESCAPED=$(echo "$COMPANY_ADDRESS" | sed 's/"/\\"/g' | tr '\n' ' ')
COMPANY_ATTN_ESCAPED=$(echo "$COMPANY_ATTN" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/insurance_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "initial_max_id": ${INITIAL_MAX_ID:-0},
    "task_start_timestamp": ${TASK_START:-0},
    "company_found": $COMPANY_FOUND,
    "newly_created": $NEWLY_CREATED,
    "company": {
        "id": "$COMPANY_ID",
        "name": "$COMPANY_NAME_ESCAPED",
        "attn": "$COMPANY_ATTN_ESCAPED",
        "address": "$COMPANY_ADDRESS_ESCAPED",
        "city": "$COMPANY_CITY",
        "state": "$COMPANY_STATE",
        "zip": "$COMPANY_ZIP",
        "phone": "$COMPANY_PHONE",
        "cms_id": "$COMPANY_CMS_ID"
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/add_insurance_result.json 2>/dev/null || sudo rm -f /tmp/add_insurance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_insurance_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_insurance_result.json
chmod 666 /tmp/add_insurance_result.json 2>/dev/null || sudo chmod 666 /tmp/add_insurance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_insurance_result.json"
cat /tmp/add_insurance_result.json

echo ""
echo "=== Export Complete ==="