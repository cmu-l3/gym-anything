#!/bin/bash
# Export script for Admin Security Setup task

echo "=== Exporting Admin Security Setup Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define the config paths we care about
PATHS=(
    "admin/security/password_lifetime"
    "admin/security/password_is_forced"
    "admin/security/lockout_failures"
    "admin/security/lockout_threshold"
    "admin/security/session_lifetime"
)

# Build JSON manually
echo "{" > /tmp/temp_result.json

# Export current values and check modification times
for path in "${PATHS[@]}"; do
    # Get Value
    val=$(magento_query "SELECT value FROM core_config_data WHERE path='$path'" 2>/dev/null | tail -1 | tr -d '[:space:]')
    
    # Get Update Time (if available in schema, usually updated_at column exists in core_config_data)
    updated_at=$(magento_query "SELECT updated_at FROM core_config_data WHERE path='$path'" 2>/dev/null | tail -1)
    
    # Check if updated recently (simple string check, verifier does logic)
    echo "  \"$path\": \"$val\"," >> /tmp/temp_result.json
    echo "  \"${path}_updated_at\": \"$updated_at\"," >> /tmp/temp_result.json
done

echo "  \"task_start_timestamp\": \"$TASK_START\"," >> /tmp/temp_result.json
echo "  \"export_timestamp\": \"$(date -Iseconds)\"" >> /tmp/temp_result.json
echo "}" >> /tmp/temp_result.json

# Securely copy to final location
safe_write_json "/tmp/temp_result.json" "/tmp/admin_security_result.json"

echo "Result exported to /tmp/admin_security_result.json"
cat /tmp/admin_security_result.json
echo ""
echo "=== Export Complete ==="