#!/bin/bash
# Export script for configure_editorial_workflow task (post_task hook)
# Checks the 3 expected posts for correct author, category, status, and schedule.

echo "=== Exporting configure_editorial_workflow result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Helper function to check a post
# ============================================================
check_editorial_post() {
    local expected_title="$1"
    local expected_author="$2"
    local expected_category="$3"
    local expected_status="$4"
    local expected_date="$5"  # YYYY-MM-DD or empty

    local post_id=""
    local found="false"
    local author_correct="false"
    local category_correct="false"
    local status_correct="false"
    local date_correct="false"
    local actual_author=""
    local actual_category=""
    local actual_status=""
    local actual_date=""
    local content_length=0

    # Find post by title
    post_id=$(wp_db_query "SELECT ID FROM wp_posts
        WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$expected_title'))
        AND post_type='post'
        ORDER BY ID DESC LIMIT 1")

    if [ -n "$post_id" ]; then
        found="true"
        echo "  Found post '$expected_title' (ID: $post_id)"

        # Get post details
        actual_status=$(wp_db_query "SELECT post_status FROM wp_posts WHERE ID=$post_id")
        actual_date=$(wp_db_query "SELECT post_date FROM wp_posts WHERE ID=$post_id")
        local author_id=$(wp_db_query "SELECT post_author FROM wp_posts WHERE ID=$post_id")

        # Get author login name
        actual_author=$(wp_db_query "SELECT user_login FROM wp_users WHERE ID=$author_id")

        # Get content length (word count)
        local content=$(wp_db_query "SELECT post_content FROM wp_posts WHERE ID=$post_id")
        content_length=$(echo "$content" | sed 's/<[^>]*>//g' | wc -w)

        # Get categories
        actual_category=$(get_post_categories "$post_id")

        # Check author
        if [ "$(echo "$actual_author" | tr '[:upper:]' '[:lower:]')" = "$(echo "$expected_author" | tr '[:upper:]' '[:lower:]')" ]; then
            author_correct="true"
        fi

        # Check category
        local cat_lower=$(echo "$actual_category" | tr '[:upper:]' '[:lower:]')
        local expected_cat_lower=$(echo "$expected_category" | tr '[:upper:]' '[:lower:]')
        if echo "$cat_lower" | grep -q "$expected_cat_lower"; then
            category_correct="true"
        fi

        # Check status
        if [ "$(echo "$actual_status" | tr '[:upper:]' '[:lower:]')" = "$(echo "$expected_status" | tr '[:upper:]' '[:lower:]')" ]; then
            status_correct="true"
        fi

        # Check date (if expected)
        if [ -n "$expected_date" ]; then
            if echo "$actual_date" | grep -q "$expected_date"; then
                date_correct="true"
            fi
        else
            date_correct="true"  # No date requirement
        fi

        echo "    Status: $actual_status (expected: $expected_status) - $([ "$status_correct" = "true" ] && echo OK || echo WRONG)"
        echo "    Author: $actual_author (expected: $expected_author) - $([ "$author_correct" = "true" ] && echo OK || echo WRONG)"
        echo "    Category: $actual_category (expected: $expected_category) - $([ "$category_correct" = "true" ] && echo OK || echo WRONG)"
        echo "    Date: $actual_date (expected: $expected_date) - $([ "$date_correct" = "true" ] && echo OK || echo WRONG)"
        echo "    Content words: $content_length"
    else
        echo "  Post '$expected_title' NOT FOUND"
    fi

    echo "{\"found\": $found, \"author_correct\": $author_correct, \"category_correct\": $category_correct, \"status_correct\": $status_correct, \"date_correct\": $date_correct, \"actual_author\": \"$actual_author\", \"actual_category\": \"$(echo "$actual_category" | sed 's/"/\\"/g')\", \"actual_status\": \"$actual_status\", \"actual_date\": \"$actual_date\", \"content_words\": $content_length}"
}

echo "Checking editorial posts:"

POST1_JSON=$(check_editorial_post "Q1 2026 Revenue Analysis" "editor" "News" "future" "2026-03-15")
POST2_JSON=$(check_editorial_post "Spring Product Launch Preview" "author" "Technology" "future" "2026-03-20")
POST3_JSON=$(check_editorial_post "Annual Team Building Event Recap" "contributor" "Lifestyle" "pending" "")

# Extract JSON lines
P1_JSON=$(echo "$POST1_JSON" | tail -1)
P2_JSON=$(echo "$POST2_JSON" | tail -1)
P3_JSON=$(echo "$POST3_JSON" | tail -1)

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "posts": {
        "q1_revenue": $P1_JSON,
        "spring_launch": $P2_JSON,
        "team_building": $P3_JSON
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/configure_editorial_workflow_result.json 2>/dev/null || sudo rm -f /tmp/configure_editorial_workflow_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_editorial_workflow_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_editorial_workflow_result.json
chmod 666 /tmp/configure_editorial_workflow_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_editorial_workflow_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/configure_editorial_workflow_result.json"
cat /tmp/configure_editorial_workflow_result.json
echo ""
echo "=== Export complete ==="
