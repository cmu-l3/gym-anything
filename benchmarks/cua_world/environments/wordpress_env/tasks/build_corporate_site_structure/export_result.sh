#!/bin/bash
# Export script for build_corporate_site_structure task (post_task hook)
# Checks page hierarchy, reading settings, and site identity.

echo "=== Exporting build_corporate_site_structure result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Check site title and tagline
# ============================================================
CURRENT_TITLE=$(wp_cli option get blogname)
CURRENT_TAGLINE=$(wp_cli option get blogdescription)
echo "Site title: $CURRENT_TITLE"
echo "Tagline: $CURRENT_TAGLINE"

TITLE_CORRECT="false"
if echo "$CURRENT_TITLE" | tr '[:upper:]' '[:lower:]' | grep -q "nexgen solutions"; then
    TITLE_CORRECT="true"
fi

TAGLINE_CORRECT="false"
if echo "$CURRENT_TAGLINE" | tr '[:upper:]' '[:lower:]' | grep -q "innovative technology consulting"; then
    TAGLINE_CORRECT="true"
fi

# ============================================================
# Check reading settings (static front page)
# ============================================================
SHOW_ON_FRONT=$(wp_cli option get show_on_front)
PAGE_ON_FRONT=$(wp_cli option get page_on_front)
echo "show_on_front: $SHOW_ON_FRONT"
echo "page_on_front: $PAGE_ON_FRONT"

STATIC_FRONT="false"
if [ "$SHOW_ON_FRONT" = "page" ]; then
    STATIC_FRONT="true"
fi

# ============================================================
# Check pages
# ============================================================
check_page() {
    local expected_title="$1"
    local expected_parent_title="$2"  # empty string for no parent

    local page_id=""
    local found="false"
    local parent_correct="false"
    local content_length=0
    local content_sufficient="false"

    # Find page by title
    page_id=$(wp_db_query "SELECT ID FROM wp_posts
        WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$expected_title'))
        AND post_type='page'
        AND post_status='publish'
        ORDER BY ID DESC LIMIT 1")

    if [ -n "$page_id" ]; then
        found="true"

        # Get content length
        local content=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$page_id")
        # Strip HTML tags for word count
        local word_count=$(echo "$content" | sed 's/<[^>]*>//g' | wc -w)
        content_length=$word_count
        if [ "$word_count" -ge 30 ]; then
            content_sufficient="true"
        fi

        # Check parent
        local actual_parent_id=$(wp_db_query "SELECT post_parent FROM wp_posts WHERE ID=$page_id")

        if [ -z "$expected_parent_title" ] || [ "$expected_parent_title" = "none" ]; then
            # Should have no parent (parent_id = 0)
            if [ "$actual_parent_id" = "0" ] || [ -z "$actual_parent_id" ]; then
                parent_correct="true"
            fi
        else
            # Should have specific parent
            local expected_parent_id=$(wp_db_query "SELECT ID FROM wp_posts
                WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$expected_parent_title'))
                AND post_type='page'
                AND post_status='publish'
                ORDER BY ID DESC LIMIT 1")
            if [ -n "$expected_parent_id" ] && [ "$actual_parent_id" = "$expected_parent_id" ]; then
                parent_correct="true"
            fi
        fi

        echo "  Page '$expected_title' (ID: $page_id): parent_correct=$parent_correct, words=$word_count"
    else
        echo "  Page '$expected_title': NOT FOUND"
    fi

    echo "{\"found\": $found, \"parent_correct\": $parent_correct, \"content_sufficient\": $content_sufficient, \"word_count\": $content_length}"
}

echo ""
echo "Checking required pages:"

SERVICES_JSON=$(check_page "Services" "none")
WEB_DEV_JSON=$(check_page "Web Development" "Services")
MOBILE_JSON=$(check_page "Mobile Apps" "Services")
CLOUD_JSON=$(check_page "Cloud Solutions" "Services")
ABOUT_JSON=$(check_page "About" "none")
CAREERS_JSON=$(check_page "Careers" "none")

# Extract last line (JSON) from each
P_SERVICES=$(echo "$SERVICES_JSON" | tail -1)
P_WEB_DEV=$(echo "$WEB_DEV_JSON" | tail -1)
P_MOBILE=$(echo "$MOBILE_JSON" | tail -1)
P_CLOUD=$(echo "$CLOUD_JSON" | tail -1)
P_ABOUT=$(echo "$ABOUT_JSON" | tail -1)
P_CAREERS=$(echo "$CAREERS_JSON" | tail -1)

# Check if front page is Services
FRONT_PAGE_IS_SERVICES="false"
if [ "$STATIC_FRONT" = "true" ] && [ -n "$PAGE_ON_FRONT" ] && [ "$PAGE_ON_FRONT" != "0" ]; then
    FRONT_PAGE_TITLE=$(wp_db_query "SELECT post_title FROM wp_posts WHERE ID=$PAGE_ON_FRONT AND post_type='page'")
    if echo "$FRONT_PAGE_TITLE" | tr '[:upper:]' '[:lower:]' | grep -q "services"; then
        FRONT_PAGE_IS_SERVICES="true"
    fi
    echo "Front page title: $FRONT_PAGE_TITLE (is Services: $FRONT_PAGE_IS_SERVICES)"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "site_identity": {
        "title": "$(json_escape "$CURRENT_TITLE")",
        "tagline": "$(json_escape "$CURRENT_TAGLINE")",
        "title_correct": $TITLE_CORRECT,
        "tagline_correct": $TAGLINE_CORRECT
    },
    "reading_settings": {
        "show_on_front": "$SHOW_ON_FRONT",
        "page_on_front": "$PAGE_ON_FRONT",
        "static_front_page": $STATIC_FRONT,
        "front_page_is_services": $FRONT_PAGE_IS_SERVICES
    },
    "pages": {
        "services": $P_SERVICES,
        "web_development": $P_WEB_DEV,
        "mobile_apps": $P_MOBILE,
        "cloud_solutions": $P_CLOUD,
        "about": $P_ABOUT,
        "careers": $P_CAREERS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/build_corporate_site_structure_result.json 2>/dev/null || sudo rm -f /tmp/build_corporate_site_structure_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/build_corporate_site_structure_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/build_corporate_site_structure_result.json
chmod 666 /tmp/build_corporate_site_structure_result.json 2>/dev/null || sudo chmod 666 /tmp/build_corporate_site_structure_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/build_corporate_site_structure_result.json"
cat /tmp/build_corporate_site_structure_result.json
echo ""
echo "=== Export complete ==="
