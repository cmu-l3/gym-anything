#!/bin/bash
echo "=== Exporting enable_directory_browsing result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Define Targets
TARGET_DIR="/home/acmecorp/public_html/downloads"
TARGET_URL="http://acmecorp.test/downloads/"
EXPECTED_FILES=("acme_driver_v2.4.exe" "user_manual_2025.pdf" "release_notes.txt")

# 3. Check Filesystem
DIR_EXISTS="false"
FILES_COUNT=0
FILES_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -d "$TARGET_DIR" ]; then
    DIR_EXISTS="true"
    
    # Check for the 3 specific files
    for fname in "${EXPECTED_FILES[@]}"; do
        if [ -f "$TARGET_DIR/$fname" ]; then
            FILES_COUNT=$((FILES_COUNT + 1))
            
            # Check timestamp (anti-gaming)
            F_MTIME=$(stat -c %Y "$TARGET_DIR/$fname" 2>/dev/null || echo "0")
            if [ "$F_MTIME" -gt "$TASK_START" ]; then
                FILES_CREATED_DURING_TASK="true"
            fi
        fi
    done
fi

# 4. Check Apache Configuration (Static Analysis)
# Look for Options +Indexes or Options All in the config file for acmecorp
APACHE_CONFIG=$(find /etc/apache2/sites-available -name "*acmecorp.test.conf" | head -1)
CONFIG_HAS_INDEXES="false"

if [ -f "$APACHE_CONFIG" ]; then
    # Grep for likely configurations. 
    # Valid: "Options +Indexes", "Options Indexes", "Options All", "Options ... Indexes ..."
    if grep -E "Options.*Indexes|Options.*All" "$APACHE_CONFIG" | grep -v "\-Indexes" > /dev/null; then
        CONFIG_HAS_INDEXES="true"
    fi
fi

# 5. Check HTTP Behavior (Dynamic Analysis - The Gold Standard)
# We curl the directory. 
# Expectation: 200 OK (not 403) AND body contains filenames.

HTTP_CODE=$(curl -s -o /tmp/curl_body.txt -w "%{http_code}" "$TARGET_URL" || echo "000")
HTTP_BODY=$(cat /tmp/curl_body.txt)

# Check if body contains filenames (evidence of listing)
LISTING_VISIBLE="false"
FOUND_FILES_IN_HTML=0

for fname in "${EXPECTED_FILES[@]}"; do
    if echo "$HTTP_BODY" | grep -q "$fname"; then
        FOUND_FILES_IN_HTML=$((FOUND_FILES_IN_HTML + 1))
    fi
done

if [ "$HTTP_CODE" -eq "200" ] && [ "$FOUND_FILES_IN_HTML" -ge 3 ]; then
    LISTING_VISIBLE="true"
fi

# 6. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dir_exists": $DIR_EXISTS,
    "files_created_count": $FILES_COUNT,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "config_has_indexes": $CONFIG_HAS_INDEXES,
    "http_code": $HTTP_CODE,
    "http_listing_visible": $LISTING_VISIBLE,
    "files_found_in_html": $FOUND_FILES_IN_HTML,
    "timestamp": "$(date +%s)"
}
EOF

# Move with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="