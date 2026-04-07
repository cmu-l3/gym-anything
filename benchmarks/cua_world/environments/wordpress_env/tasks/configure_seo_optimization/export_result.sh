#!/bin/bash
# Export script for configure_seo_optimization task

echo "=== Exporting configure_seo_optimization result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# 1. Check Yoast SEO Plugin Status
# ============================================================
YOAST_ACTIVE="false"
if wp_cli plugin is-active wordpress-seo >/dev/null 2>&1; then
    YOAST_ACTIVE="true"
    echo "Yoast SEO is active"
else
    echo "Yoast SEO is NOT active"
fi

# ============================================================
# 2. Check Site-Wide SEO Settings (wpseo_titles)
# ============================================================
WPSEO_TITLES_JSON="{}"
if [ "$YOAST_ACTIVE" = "true" ]; then
    # wp-cli option get will output JSON if we ask, which safely formats serialized arrays
    RAW_JSON=$(wp_cli option get wpseo_titles --format=json 2>/dev/null)
    if [ -n "$RAW_JSON" ]; then
        WPSEO_TITLES_JSON="$RAW_JSON"
    fi
fi

# ============================================================
# 3. Check Post 1: "Getting Started with WordPress"
# ============================================================
P1_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER('Getting Started with WordPress') AND post_type='post' LIMIT 1")
P1_KW=""
P1_DESC=""

if [ -n "$P1_ID" ]; then
    echo "Found Post 1 ID: $P1_ID"
    P1_KW=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$P1_ID AND meta_key='_yoast_wpseo_focuskw' LIMIT 1")
    P1_DESC=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$P1_ID AND meta_key='_yoast_wpseo_metadesc' LIMIT 1")
    echo "P1 KW: $P1_KW"
    echo "P1 DESC length: ${#P1_DESC}"
else
    echo "Post 1 NOT FOUND!"
fi

# ============================================================
# 4. Check Post 2: "10 Essential WordPress Plugins Every Site Needs"
# ============================================================
P2_ID=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) LIKE LOWER('%10 Essential WordPress Plugins%') AND post_type='post' LIMIT 1")
P2_KW=""
P2_DESC=""

if [ -n "$P2_ID" ]; then
    echo "Found Post 2 ID: $P2_ID"
    P2_KW=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$P2_ID AND meta_key='_yoast_wpseo_focuskw' LIMIT 1")
    P2_DESC=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$P2_ID AND meta_key='_yoast_wpseo_metadesc' LIMIT 1")
    echo "P2 KW: $P2_KW"
    echo "P2 DESC length: ${#P2_DESC}"
else
    echo "Post 2 NOT FOUND!"
fi

# ============================================================
# 5. Export JSON
# ============================================================
# Escape strings to be JSON safe
P1_KW_ESC=$(echo "$P1_KW" | sed 's/"/\\"/g' | tr -d '\n')
P1_DESC_ESC=$(echo "$P1_DESC" | sed 's/"/\\"/g' | tr -d '\n')
P2_KW_ESC=$(echo "$P2_KW" | sed 's/"/\\"/g' | tr -d '\n')
P2_DESC_ESC=$(echo "$P2_DESC" | sed 's/"/\\"/g' | tr -d '\n')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "yoast_active": $YOAST_ACTIVE,
    "wpseo_titles": $WPSEO_TITLES_JSON,
    "p1": {
        "id": "${P1_ID:-null}",
        "focuskw": "$P1_KW_ESC",
        "metadesc": "$P1_DESC_ESC"
    },
    "p2": {
        "id": "${P2_ID:-null}",
        "focuskw": "$P2_KW_ESC",
        "metadesc": "$P2_DESC_ESC"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/seo_optimization_result.json 2>/dev/null || sudo rm -f /tmp/seo_optimization_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/seo_optimization_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/seo_optimization_result.json
chmod 666 /tmp/seo_optimization_result.json 2>/dev/null || sudo chmod 666 /tmp/seo_optimization_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/seo_optimization_result.json"
cat /tmp/seo_optimization_result.json
echo ""
echo "=== Export Complete ==="