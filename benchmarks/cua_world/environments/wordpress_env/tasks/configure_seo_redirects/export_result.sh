#!/bin/bash
# Export script for configure_seo_redirects task
# Queries the local web server to verify redirects

echo "=== Exporting configure_seo_redirects result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if homepage is functional (avoids 500 Internal Server Error if .htaccess is broken)
HOMEPAGE_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
echo "Homepage HTTP code: $HOMEPAGE_CODE"

# Function to get HTTP code and redirect location
check_redirect() {
    local path=$1
    # -w "%{http_code}|%{redirect_url}" returns e.g. "301|http://localhost/about-us/"
    local out=$(curl -s -o /dev/null -w "%{http_code}|%{redirect_url}" "http://localhost${path}")
    echo "$out"
}

# Test all 4 deprecated paths
R1_OUT=$(check_redirect "/company-history/")
R2_OUT=$(check_redirect "/services/legacy-support/")
R3_OUT=$(check_redirect "/contact-us-2023/")
R4_OUT=$(check_redirect "/blog/news-updates/")

# Parse results
R1_CODE=$(echo "$R1_OUT" | cut -d'|' -f1)
R1_LOC=$(echo "$R1_OUT" | cut -d'|' -f2 | sed 's/"/\\"/g')

R2_CODE=$(echo "$R2_OUT" | cut -d'|' -f1)
R2_LOC=$(echo "$R2_OUT" | cut -d'|' -f2 | sed 's/"/\\"/g')

R3_CODE=$(echo "$R3_OUT" | cut -d'|' -f1)
R3_LOC=$(echo "$R3_OUT" | cut -d'|' -f2 | sed 's/"/\\"/g')

R4_CODE=$(echo "$R4_OUT" | cut -d'|' -f1)
R4_LOC=$(echo "$R4_OUT" | cut -d'|' -f2 | sed 's/"/\\"/g')

echo "R1 (/company-history/): Code $R1_CODE -> $R1_LOC"
echo "R2 (/services/legacy-support/): Code $R2_CODE -> $R2_LOC"
echo "R3 (/contact-us-2023/): Code $R3_CODE -> $R3_LOC"
echo "R4 (/blog/news-updates/): Code $R4_CODE -> $R4_LOC"

# Get modification time of .htaccess to see if agent edited it
HTACCESS_MTIME=$(stat -c %Y /var/www/html/wordpress/.htaccess 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
HTACCESS_MODIFIED="false"
if [ "$HTACCESS_MTIME" -gt "$TASK_START" ]; then
    HTACCESS_MODIFIED="true"
fi

# Check if any redirect plugins are active
ACTIVE_PLUGINS=$(cd /var/www/html/wordpress && wp plugin list --status=active --field=name --allow-root 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "homepage_code": "$HOMEPAGE_CODE",
    "htaccess_modified": $HTACCESS_MODIFIED,
    "active_plugins": "$ACTIVE_PLUGINS",
    "redirects": {
        "r1": {
            "code": "$R1_CODE",
            "location": "$R1_LOC"
        },
        "r2": {
            "code": "$R2_CODE",
            "location": "$R2_LOC"
        },
        "r3": {
            "code": "$R3_CODE",
            "location": "$R3_LOC"
        },
        "r4": {
            "code": "$R4_CODE",
            "location": "$R4_LOC"
        }
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/configure_seo_redirects_result.json 2>/dev/null || sudo rm -f /tmp/configure_seo_redirects_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_seo_redirects_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_seo_redirects_result.json
chmod 666 /tmp/configure_seo_redirects_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_seo_redirects_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/configure_seo_redirects_result.json"
cat /tmp/configure_seo_redirects_result.json
echo "=== Export complete ==="