#!/bin/bash
echo "=== Exporting configure_website_redirects results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record end time and paths
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
APACHE_CONF="/etc/apache2/sites-available/acmecorp.test.conf"

# 2. Check Apache Config Modification
CONFIG_MODIFIED="false"
if [ -f "$APACHE_CONF" ]; then
    CURRENT_HASH=$(md5sum "$APACHE_CONF" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/initial_apache_config_hash.txt 2>/dev/null || echo "none")
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        CONFIG_MODIFIED="true"
    fi
    
    # Also check timestamp
    CONFIG_MTIME=$(stat -c %Y "$APACHE_CONF" 2>/dev/null || echo "0")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED_TIMESTAMP="true"
    else
        CONFIG_MODIFIED_TIMESTAMP="false"
    fi
fi

# 3. Verify Redirects using curl (Functional Testing)
# We use curl -I (head) to check headers without downloading body
# We look for HTTP/1.1 301 or 302 and the Location header

verify_redirect() {
    local path="$1"
    local output_file="$2"
    
    echo "Testing $path..."
    # -I for headers only, -s for silent
    curl -Is "http://acmecorp.test${path}" > "$output_file"
    cat "$output_file"
}

# Test Redirect 1 (301)
verify_redirect "/old-products" "/tmp/redirect1_headers.txt"
R1_STATUS=$(grep -oE "HTTP/[0-9.]+ [0-9]+" /tmp/redirect1_headers.txt | awk '{print $2}' || echo "0")
R1_LOCATION=$(grep -i "Location:" /tmp/redirect1_headers.txt | awk '{print $2}' | tr -d '\r' || echo "none")

# Test Redirect 2 (302)
verify_redirect "/survey" "/tmp/redirect2_headers.txt"
R2_STATUS=$(grep -oE "HTTP/[0-9.]+ [0-9]+" /tmp/redirect2_headers.txt | awk '{print $2}' || echo "0")
R2_LOCATION=$(grep -i "Location:" /tmp/redirect2_headers.txt | awk '{print $2}' | tr -d '\r' || echo "none")

# 4. Read Apache config content for static analysis (backup verification)
CONFIG_CONTENT=""
if [ -f "$APACHE_CONF" ]; then
    # Read only the relevant lines to keep JSON small
    CONFIG_CONTENT=$(grep -i "Redirect" "$APACHE_CONF" || echo "")
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_modified": $CONFIG_MODIFIED,
    "config_modified_timestamp": $CONFIG_MODIFIED_TIMESTAMP,
    "redirect1": {
        "path": "/old-products",
        "actual_status": "$R1_STATUS",
        "actual_location": "$R1_LOCATION"
    },
    "redirect2": {
        "path": "/survey",
        "actual_status": "$R2_STATUS",
        "actual_location": "$R2_LOCATION"
    },
    "apache_config_snippets": $(echo "$CONFIG_CONTENT" | jq -R -s '.'),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json