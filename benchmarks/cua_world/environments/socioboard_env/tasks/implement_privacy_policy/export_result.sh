#!/bin/bash
echo "=== Exporting implement_privacy_policy result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Clear laravel caches to ensure we're getting fresh content before testing HTTP
sudo -u ga bash -c 'cd /opt/socioboard/socioboard-web-php && php artisan route:clear 2>/dev/null || true'
sudo -u ga bash -c 'cd /opt/socioboard/socioboard-web-php && php artisan view:clear 2>/dev/null || true'

# Perform HTTP requests
HTTP_CODE_INDEX=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
curl -s http://localhost/ > /tmp/http_index.html
HTTP_CODE_PRIVACY=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/privacy)
curl -s http://localhost/privacy > /tmp/http_privacy.html

# Check file modifications
ROUTES_FILE="/opt/socioboard/socioboard-web-php/routes/web.php"
PRIVACY_VIEW="/opt/socioboard/socioboard-web-php/resources/views/privacy.blade.php"

ROUTES_EXISTS="false"
ROUTES_MTIME="0"
ROUTES_CONTAINS_PRIVACY="false"
if [ -f "$ROUTES_FILE" ]; then
    ROUTES_EXISTS="true"
    ROUTES_MTIME=$(stat -c %Y "$ROUTES_FILE" 2>/dev/null || echo "0")
    if grep -q "privacy" "$ROUTES_FILE"; then
        ROUTES_CONTAINS_PRIVACY="true"
    fi
fi

PRIVACY_VIEW_EXISTS="false"
PRIVACY_VIEW_MTIME="0"
if [ -f "$PRIVACY_VIEW" ]; then
    PRIVACY_VIEW_EXISTS="true"
    PRIVACY_VIEW_MTIME=$(stat -c %Y "$PRIVACY_VIEW" 2>/dev/null || echo "0")
fi

# Find any modified view files containing the link
MODIFIED_VIEWS=$(find /opt/socioboard/socioboard-web-php/resources/views -type f -newermt "@$TASK_START" 2>/dev/null || echo "")
LINK_FOUND_IN_FILES="false"
for f in $MODIFIED_VIEWS; do
    if grep -q "privacy-link" "$f" 2>/dev/null; then
        LINK_FOUND_IN_FILES="true"
        break
    fi
done

# Create JSON result using Python to safely handle HTML content escaping
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << EOF > "$TEMP_JSON"
import json
import os

def read_file(path):
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    except:
        return ""

index_body = read_file('/tmp/http_index.html')
privacy_body = read_file('/tmp/http_privacy.html')
privacy_view = read_file('$PRIVACY_VIEW') if "$PRIVACY_VIEW_EXISTS" == "true" else ""

data = {
    "task_start": $TASK_START,
    "http_index": {
        "code": "$HTTP_CODE_INDEX",
        "body_contains_link": 'id="privacy-link"' in index_body or "privacy-link" in index_body,
        "body_contains_href": 'href="/privacy"' in index_body or "href='/privacy'" in index_body
    },
    "http_privacy": {
        "code": "$HTTP_CODE_PRIVACY",
        "body_length": len(privacy_body),
        "body_contains_gdpr": "GDPR compliance" in privacy_body,
        "body_contains_erasure": "Right to Erasure" in privacy_body,
        "body_contains_dpo": "Data Protection Officer" in privacy_body
    },
    "files": {
        "routes_exists": "$ROUTES_EXISTS" == "true",
        "routes_mtime": $ROUTES_MTIME,
        "routes_contains_privacy": "$ROUTES_CONTAINS_PRIVACY" == "true",
        "privacy_view_exists": "$PRIVACY_VIEW_EXISTS" == "true",
        "privacy_view_mtime": $PRIVACY_VIEW_MTIME,
        "privacy_view_contains_dpo": "Data Protection Officer" in privacy_view,
        "link_found_in_modified_views": "$LINK_FOUND_IN_FILES" == "true"
    }
}

with open("$TEMP_JSON", "w") as f:
    json.dump(data, f, indent=2)
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="