#!/bin/bash
# Export script for implement_custom_content_filters task
# Dynamically tests the PHP hook logic by creating exact-length posts and scraping the output

echo "=== Exporting implement_custom_content_filters result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Check if functions.php was actually modified
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FUNCTIONS_PATH="/var/www/html/wordpress/wp-content/themes/magazine-child/functions.php"
FUNCTIONS_MTIME=$(stat -c %Y "$FUNCTIONS_PATH" 2>/dev/null || echo "0")

FUNCTIONS_MODIFIED="false"
if [ "$FUNCTIONS_MTIME" -gt "$TASK_START" ]; then
    FUNCTIONS_MODIFIED="true"
fi

# 2. Check site health (ensure no fatal PHP errors were introduced)
SITE_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
SITE_HEALTHY="false"
if [ "$SITE_HTTP_CODE" = "200" ]; then
    SITE_HEALTHY="true"
fi

# ============================================================
# DYNAMIC VERIFICATION POSTS (Anti-Gaming Mechanism)
# ============================================================
# We create new posts of exact lengths to prove the code dynamically evaluates word counts.

HEALTH_CAT_ID=$(wp_cli term get category health --field=term_id 2>/dev/null)
TECH_CAT_ID=$(wp_cli term get category technology --field=term_id 2>/dev/null)

# Generate exactly 450 words for Health Post (450 / 200 = 2.25 -> 3 min)
HEALTH_WORDS=$(yes "healthword" | head -n 450 | tr '\n' ' ')
TEST_HEALTH_ID=$(wp_cli post create --post_title="Verifier Health Test" --post_content="$HEALTH_WORDS" --post_category="$HEALTH_CAT_ID" --post_status="publish" --porcelain)

# Generate exactly 100 words for Tech Post (100 / 200 = 0.5 -> 1 min)
TECH_WORDS=$(yes "techword" | head -n 100 | tr '\n' ' ')
TEST_TECH_ID=$(wp_cli post create --post_title="Verifier Tech Test" --post_content="$TECH_WORDS" --post_category="$TECH_CAT_ID" --post_status="publish" --porcelain)

# Get URLs
URL_HEALTH=$(wp_cli post list --post__in=$TEST_HEALTH_ID --field=url)
URL_TECH=$(wp_cli post list --post__in=$TEST_TECH_ID --field=url)
URL_HOME="http://localhost/?nocache=$(date +%s)"

# Fetch HTML output
HTML_HEALTH=$(curl -s "$URL_HEALTH")
HTML_TECH=$(curl -s "$URL_TECH")
HTML_HOME=$(curl -s "$URL_HOME")

# ============================================================
# EVALUATE HTML OUTPUT
# ============================================================

# Health Post Checks (450 words -> 3 min, has disclaimer)
H_HAS_CORRECT_RT="false"
if echo "$HTML_HEALTH" | grep -qi "Estimated Reading Time: 3 min"; then
    H_HAS_CORRECT_RT="true"
fi

H_HAS_CLASS="false"
if echo "$HTML_HEALTH" | grep -qiE "class=[\"']reading-time[\"']"; then
    H_HAS_CLASS="true"
fi

H_HAS_DISCLAIMER="false"
if echo "$HTML_HEALTH" | grep -qi "informational purposes only"; then
    H_HAS_DISCLAIMER="true"
fi

# Tech Post Checks (100 words -> 1 min, NO disclaimer)
T_HAS_CORRECT_RT="false"
if echo "$HTML_TECH" | grep -qi "Estimated Reading Time: 1 min"; then
    T_HAS_CORRECT_RT="true"
fi

T_HAS_DISCLAIMER="false"
if echo "$HTML_TECH" | grep -qi "informational purposes only"; then
    T_HAS_DISCLAIMER="true"
fi

# Homepage Checks (Should NOT have injections due to is_single() requirement)
HOME_CLEAN="true"
if echo "$HTML_HOME" | grep -qi "Estimated Reading Time:" || echo "$HTML_HOME" | grep -qi "informational purposes only"; then
    HOME_CLEAN="false"
fi

# Clean up verification posts
wp_cli post delete $TEST_HEALTH_ID --force > /dev/null
wp_cli post delete $TEST_TECH_ID --force > /dev/null

# ============================================================
# EXPORT JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "functions_modified": $FUNCTIONS_MODIFIED,
    "site_healthy": $SITE_HEALTHY,
    "site_http_code": "$SITE_HTTP_CODE",
    "health_post": {
        "has_correct_reading_time": $H_HAS_CORRECT_RT,
        "has_reading_time_class": $H_HAS_CLASS,
        "has_disclaimer": $H_HAS_DISCLAIMER
    },
    "tech_post": {
        "has_correct_reading_time": $T_HAS_CORRECT_RT,
        "has_disclaimer": $T_HAS_DISCLAIMER
    },
    "homepage_clean": $HOME_CLEAN,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe write
rm -f /tmp/custom_filters_result.json 2>/dev/null || sudo rm -f /tmp/custom_filters_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/custom_filters_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/custom_filters_result.json
chmod 666 /tmp/custom_filters_result.json 2>/dev/null || sudo chmod 666 /tmp/custom_filters_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Exported results:"
cat /tmp/custom_filters_result.json
echo "=== Export complete ==="