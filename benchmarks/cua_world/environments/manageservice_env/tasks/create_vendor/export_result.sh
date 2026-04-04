#!/bin/bash
echo "=== Exporting Create Vendor Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query the database for the vendor
# We query multiple potential tables/columns to be robust against schema versions
# Common SDP schema: VendorDefinition table
echo "Querying database for vendor..."

# We construct a JSON object from the DB query manually
# Note: SDP uses PostgreSQL

# Try to fetch columns. We select assuming standard column names, but fallback to wildcards if needed.
# We look for a vendor matching 'ProAV Distribution' (case insensitive)
VENDOR_DATA=$(sdp_db_exec "
SELECT row_to_json(t) FROM (
    SELECT * FROM vendordefinition 
    WHERE LOWER(vendorname) LIKE '%proav distribution%'
    LIMIT 1
) t;" 2>/dev/null)

# If empty, try 'vendor' table
if [ -z "$VENDOR_DATA" ]; then
    VENDOR_DATA=$(sdp_db_exec "
    SELECT row_to_json(t) FROM (
        SELECT * FROM vendor 
        WHERE LOWER(vendorname) LIKE '%proav distribution%'
        LIMIT 1
    ) t;" 2>/dev/null)
fi

# Clean up the output (sdp_db_exec might return some noise)
VENDOR_JSON=$(echo "$VENDOR_DATA" | grep "^{" | head -n 1)

if [ -n "$VENDOR_JSON" ]; then
    VENDOR_EXISTS="true"
else
    VENDOR_EXISTS="false"
    VENDOR_JSON="{}"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vendor_exists": $VENDOR_EXISTS,
    "vendor_data": $VENDOR_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="